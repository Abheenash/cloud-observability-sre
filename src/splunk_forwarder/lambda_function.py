"""Ship CloudWatch Logs to Splunk HEC.

Why this exists: the SLOs, alarms and dashboards in this repo are CloudWatch-native,
and most of the enterprises I'm targeting centralise on Splunk. This is the seam
between the two — a CloudWatch Logs subscription filter delivers here, and this
forwards to Splunk's HTTP Event Collector.

The three things that make this different from a naive forwarder:

1. **The payload is gzipped and base64'd, and contains MANY events.** A
   subscription filter delivers a batch, not a line. Forwarding one HTTP request
   per event would be both slow and rate-limited.

2. **HEC wants newline-delimited JSON objects, not a JSON array.** Sending an
   array is the single most common reason a HEC integration silently 400s.

3. **A partial failure must not replay the whole batch.** Lambda retries the
   entire invocation on an unhandled exception, so an error after some events
   were accepted would duplicate them. Splunk HEC is all-or-nothing per request,
   so the batch is sent as one request and either succeeds or is retried whole —
   which is the only shape that is actually idempotent here.
"""

from __future__ import annotations

import base64
import gzip
import json
import os
import urllib.error
import urllib.request

HEC_URL = os.environ.get("SPLUNK_HEC_URL", "")
HEC_TOKEN_PARAM = os.environ.get("SPLUNK_HEC_TOKEN_PARAM", "")
SOURCETYPE = os.environ.get("SPLUNK_SOURCETYPE", "aws:cloudwatchlogs")
INDEX = os.environ.get("SPLUNK_INDEX", "main")
TIMEOUT = int(os.environ.get("HEC_TIMEOUT_SECONDS", "10"))
# CONTROL_MESSAGE is what CloudWatch sends to validate a new subscription. It is
# not log data and must not be forwarded, or Splunk gets a junk event per filter.
_CONTROL = "CONTROL_MESSAGE"

_ssm = None
_token_cache: str | None = None


def _token() -> str:
    """Read the HEC token from SSM Parameter Store, once per execution environment.

    The token is a bearer credential: anything holding it can write to the index.
    It is never an environment variable, because those are visible in the console
    and in every GetFunctionConfiguration call.
    """
    global _ssm, _token_cache
    if _token_cache is None:
        if not HEC_TOKEN_PARAM:
            raise RuntimeError("SPLUNK_HEC_TOKEN_PARAM is not set")
        import boto3

        if _ssm is None:
            _ssm = boto3.client("ssm")
        _token_cache = _ssm.get_parameter(Name=HEC_TOKEN_PARAM, WithDecryption=True)["Parameter"]["Value"]
    return _token_cache


def decode(event: dict) -> dict:
    """CloudWatch Logs arrives gzipped and base64-encoded under awslogs.data."""
    raw = base64.b64decode(event["awslogs"]["data"])
    return json.loads(gzip.decompress(raw))


def to_hec_events(payload: dict) -> list[dict]:
    """One HEC envelope per log event, carrying the provenance Splunk needs."""
    group = payload.get("logGroup", "")
    stream = payload.get("logStream", "")
    owner = payload.get("owner", "")
    out = []
    for e in payload.get("logEvents", []):
        message = e.get("message", "")
        # The app emits one JSON object per line. Parsing it here means Splunk
        # indexes real fields instead of a quoted blob it has to re-parse at
        # search time, which is the difference between a usable index and a slow one.
        try:
            body = json.loads(message)
        except (ValueError, TypeError):
            body = {"message": message}

        out.append({
            # CloudWatch timestamps are epoch MILLISECONDS; HEC wants seconds.
            # Getting this wrong puts every event in 1970 and is invisible until
            # someone searches by time.
            "time": e["timestamp"] / 1000.0,
            "host": owner,
            "source": f"{group}:{stream}",
            "sourcetype": SOURCETYPE,
            "index": INDEX,
            "event": body,
            "fields": {"logGroup": group, "logStream": stream, "awsAccount": owner},
        })
    return out


def to_hec_body(events: list[dict]) -> bytes:
    """HEC takes CONCATENATED JSON objects, NOT a JSON array.

    Sending `[{...},{...}]` is the most common reason a HEC integration returns
    400 with an unhelpful message.
    """
    return "".join(json.dumps(e, separators=(",", ":")) for e in events).encode()


def handler(event, context):
    payload = decode(event)

    if payload.get("messageType") == _CONTROL:
        # Subscription validation ping — acknowledge, forward nothing.
        return {"forwarded": 0, "control": True}

    events = to_hec_events(payload)
    if not events:
        return {"forwarded": 0}

    if not HEC_URL.lower().startswith("https://"):
        raise RuntimeError("SPLUNK_HEC_URL must be https — a HEC token is a bearer credential")

    req = urllib.request.Request(  # noqa: S310 — scheme checked above
        HEC_URL,
        data=to_hec_body(events),
        headers={
            "Authorization": f"Splunk {_token()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        # One request for the whole batch: HEC is all-or-nothing per request, so
        # this is the only shape where a Lambda retry cannot duplicate events.
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:  # noqa: S310
            body = r.read(4096).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        detail = e.read(1024).decode("utf-8", "replace")
        # Raise: Lambda retries the invocation, and the subscription filter's
        # async retry plus the DLQ are what stop data being silently dropped.
        raise RuntimeError(f"HEC rejected the batch: {e.code} {detail}") from e

    print(json.dumps({"forwarded": len(events), "logGroup": payload.get("logGroup"), "hec": body[:200]}))
    return {"forwarded": len(events)}
