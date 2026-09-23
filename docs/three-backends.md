# The same golden signals, three backends

This repo now expresses one service's health three ways: **CloudWatch** (native),
**Splunk** (log search), and **Datadog** (SaaS monitoring). That is not
redundancy for its own sake — each is what a different employer already runs, and
the differences are real enough to be worth writing down.

| | CloudWatch | Splunk | Datadog |
|---|---|---|---|
| What it is | metrics + alarms, in-account | **log search** | metrics + APM + logs, SaaS |
| Alert unit | `aws_cloudwatch_metric_alarm` | saved search | `datadog_monitor` |
| Alert expression | metric + statistic + threshold; **metric math** for anything else | SPL | **one query string** |
| SLO | arithmetic inside a burn-rate alarm | — | **a first-class object** |
| Missing data | `treat_missing_data` | n/a | `notify_no_data` |
| Cost driver | per metric, per alarm, per dashboard | **per GB ingested per day** | per host, per custom metric |
| Where it lives | the account | your SIEM | a vendor |

## Three things that genuinely differ

### 1. Datadog has an SLO; CloudWatch does not

In `burn_rate.tf` the 99.5% target exists only as **arithmetic inside an alarm** —
`14.4 * 0.005`. There is no object called "the SLO", nothing to query for
remaining error budget, and nothing that fails if two alarms disagree about the
target.

`datadog_service_level_objective.availability` is a resource with a target, a
window and a queryable budget. That is a real modelling advantage, and it is why
`tests.tftest.hcl` asserts the Datadog target **matches** the number the
CloudWatch burn-rate alarms are computed against. If they drift, the same
incident pages on one backend and not the other — which is worse than having one.

### 2. A Datadog monitor is one string, and that cuts both ways

The 5xx ratio here is a division across two metrics. CloudWatch needs a metric
**math** expression with `m1/m2` and referenced metric ids; Datadog takes:

```
sum(last_5m):sum:aws.apigateway.5xxerror{...}.as_count()
  / sum:aws.apigateway.count{...}.as_count() > 0.005
```

More expressive, and easier to get subtly wrong — the whole thing is a string
that is only validated server-side, so a typo in a tag filter yields a monitor
that never fires rather than an error at apply time.

### 3. Splunk's cost driver changes what you send

CloudWatch charges per metric and per alarm; Datadog per host and custom metric.
**Splunk charges per GB ingested per day**, which makes the subscription filter's
`filter_pattern` a cost decision, not a tidiness one. Shipping every Lambda
`START`/`END`/`REPORT` line roughly triples volume for no diagnostic gain, so
`splunk.tf` narrows to the app's own structured JSON lines.

## What did not change

The reasoning. All three carry the same split:

- an **error-ratio** alert that deliberately does **not** fire on missing data,
  because no requests means no errors and a quiet night is not an outage; and
- a **traffic/volume** alert that **must** fire on silence, because an API
  emitting nothing at all is precisely what the ratio alert cannot see.

That pairing is asserted in `tests.tftest.hcl` for both the CloudWatch and the
Datadog side. It is the same conclusion I reached — and initially got wrong — when
writing the Prometheus rules in `aws-eks-platform`.

## Status

**Both Splunk and Datadog are off by default** (`splunk_hec_url` and
`datadog_api_key` empty create nothing). There is no Splunk instance and no
Datadog org behind this account; integrations pointing at neither would just fail
or fill a DLQ. The configuration is validated, unit-tested and scanned — and says
plainly that it has never talked to either vendor.
