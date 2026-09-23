"""The Splunk HEC forwarder.

Each test corresponds to a way this integration silently fails in production:
a JSON array instead of concatenated objects, milliseconds sent as seconds, a
control message forwarded as data, and a plaintext URL leaking a bearer token.
"""
import base64
import gzip
import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src" / "splunk_forwarder"))

import lambda_function as fwd


def cw_event(log_events, group="/aws/lambda/sfs-issue-url", stream="s1", message_type="DATA_MESSAGE"):
    payload = {
        "messageType": message_type, "owner": "111122223333",
        "logGroup": group, "logStream": stream, "logEvents": log_events,
    }
    blob = gzip.compress(json.dumps(payload).encode())
    return {"awslogs": {"data": base64.b64encode(blob).decode()}}


def test_decodes_gzipped_base64_batches():
    ev = cw_event([{"id": "1", "timestamp": 1700000000000, "message": "hello"}])
    assert fwd.decode(ev)["logGroup"] == "/aws/lambda/sfs-issue-url"


def test_timestamps_convert_milliseconds_to_seconds():
    """CloudWatch is epoch ms; HEC is epoch seconds. Get this wrong and every
    event lands in 1970 — invisible until someone searches by time."""
    payload = fwd.decode(cw_event([{"id": "1", "timestamp": 1700000000000, "message": "x"}]))
    out = fwd.to_hec_events(payload)
    assert out[0]["time"] == 1700000000.0


def test_json_log_lines_are_indexed_as_fields_not_a_blob():
    """The app emits one JSON object per line. Parsing here means Splunk indexes
    real fields instead of re-parsing a quoted string at search time."""
    line = json.dumps({"rid": "abc", "status": 500, "ms": 12.3})
    payload = fwd.decode(cw_event([{"id": "1", "timestamp": 1700000000000, "message": line}]))
    body = fwd.to_hec_events(payload)[0]["event"]
    assert body["status"] == 500 and body["rid"] == "abc"


def test_non_json_lines_still_forward():
    payload = fwd.decode(cw_event([{"id": "1", "timestamp": 1700000000000, "message": "START RequestId: x"}]))
    assert fwd.to_hec_events(payload)[0]["event"] == {"message": "START RequestId: x"}


def test_body_is_concatenated_objects_not_a_json_array():
    """The single most common reason a HEC integration 400s."""
    events = [{"time": 1.0, "event": {"a": 1}}, {"time": 2.0, "event": {"b": 2}}]
    body = fwd.to_hec_body(events).decode()
    assert not body.startswith("["), "HEC rejects a JSON array"
    assert body.count('"time"') == 2
    # Concatenated objects: }{  with no comma between them.
    assert "}{" in body
    with pytest.raises(ValueError):
        json.loads(body)  # deliberately NOT a single JSON document


def test_control_messages_are_not_forwarded(monkeypatch):
    """CloudWatch sends CONTROL_MESSAGE to validate a new subscription. Forwarding
    it puts a junk event in the index for every filter created."""
    monkeypatch.setattr(fwd, "HEC_URL", "https://splunk.example.invalid/services/collector")
    ev = cw_event([{"id": "1", "timestamp": 1700000000000, "message": "CWL CONTROL MESSAGE"}],
                  message_type="CONTROL_MESSAGE")
    assert fwd.handler(ev, None) == {"forwarded": 0, "control": True}


def test_refuses_a_plaintext_hec_url(monkeypatch):
    """The HEC token is a bearer credential. Over http it is on the wire in clear."""
    monkeypatch.setattr(fwd, "HEC_URL", "http://splunk.example.invalid/services/collector")
    ev = cw_event([{"id": "1", "timestamp": 1700000000000, "message": "x"}])
    with pytest.raises(RuntimeError, match="must be https"):
        fwd.handler(ev, None)


def test_empty_batch_sends_nothing(monkeypatch):
    monkeypatch.setattr(fwd, "HEC_URL", "https://splunk.example.invalid/services/collector")
    assert fwd.handler(cw_event([]), None) == {"forwarded": 0}


def test_provenance_fields_are_attached():
    payload = fwd.decode(cw_event([{"id": "1", "timestamp": 1700000000000, "message": "x"}]))
    e = fwd.to_hec_events(payload)[0]
    assert e["source"] == "/aws/lambda/sfs-issue-url:s1"
    assert e["fields"]["awsAccount"] == "111122223333"
    assert e["host"] == "111122223333"
