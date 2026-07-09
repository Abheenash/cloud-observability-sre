# Cloud Observability & Incident Response — operating a live serverless service on AWS

Take a **real, running production service** — my [serverless-file-share](https://github.com/Abheenash/serverless-file-share) app (live at `share.abheenash.com`) — and make it **observable and operable**: golden-signal dashboards, distributed tracing, SLOs with error budgets, automated alerting, and a documented incident-response runbook — capped by a demo that induces a real failure, catches it, and recovers.

**Status:** ✅ All stages complete — observing the **live** serverless-file-share stack; an induced incident was detected and recovered ([docs/stage5.md](docs/stage5.md)). See the [architecture](docs/architecture.md) and [runbook](docs/runbook.md).

## Why this project

Projects that *build* things are common; projects that prove you can *operate* them in production are rare — that's the gap this fills. It's the third of a three-project arc:

- **[serverless-file-share](https://github.com/Abheenash/serverless-file-share)** — *build securely*
- **[secure-container-pipeline](https://github.com/Abheenash/secure-container-pipeline)** — *ship securely*
- **this** — *operate reliably*

The service under observation is **already live**, so this is genuine "run what you built" — not a toy spun up to be watched.

## What is observed

The serverless-file-share stack: **API Gateway → Lambda (issue-url / download / reaper) → S3 + DynamoDB**, encrypted with KMS.

## Target architecture

```
   serverless-file-share (LIVE)
   API Gateway · Lambda · DynamoDB · S3
        │            │            │
   structured     custom      X-Ray
     logs         metrics     traces
        │            │            │
        ▼            ▼            ▼
   ┌─────────────────────────────────────┐
   │             CloudWatch              │
   │  Logs Insights · Dashboards         │
   │  Alarms (golden signals + SLOs)     │
   └─────────────────────────────────────┘
        │                      ▲
 breach │              synthetics canary
        ▼               (probes the live API)
    SNS ──> email
        │
        ▼
  Runbook (docs/runbook.md) + failure-injection demo
```

## How it works (planned)

1. The live service emits **structured logs**, **custom + built-in metrics**, and **X-Ray traces** (active tracing enabled on the Lambdas + API Gateway).
2. **CloudWatch** aggregates them into a **golden-signals dashboard** — latency, traffic, errors, saturation — for API Gateway, Lambda, and DynamoDB.
3. **SLOs** (e.g. 99% availability, a p95-latency target) are tracked with an **error budget**; alarms fire on breach and on golden-signal thresholds.
4. A **CloudWatch Synthetics canary** probes the live API continuously for outside-in uptime.
5. Alarms notify via **SNS → email**, and each maps to a step in the **runbook**.
6. Capstone: **induce a failure** (e.g. revoke the issue-url Lambda's KMS permission so uploads break), watch the dashboard + alarm catch it, follow the runbook, and recover.

## Services and why

| Service | Role here |
|---|---|
| CloudWatch (Logs, Metrics, Dashboards, Alarms) | Core observability + alerting |
| CloudWatch Logs Insights | Query structured Lambda logs |
| X-Ray | Distributed tracing across API Gateway → Lambda → DynamoDB |
| CloudWatch Synthetics | Outside-in uptime canary against the live API |
| SNS | Alarm notifications (email) |
| Terraform | All observability infrastructure as code |
| GitHub Actions (OIDC) | CI, keyless — same pattern as the prior projects |

## Roadmap

- [x] **Stage 0** — Repo, reuse account hygiene + OIDC role, budget alarm; target = the live serverless-file-share stack
- [x] **Stage 1** — [Structured logging + CloudWatch Logs Insights queries](docs/stage1.md) over the Lambda logs
- [x] **Stage 2** — [Golden-signals dashboard](docs/stage2.md) (API Gateway / Lambda / DynamoDB) + SLO widget
- [x] **Stage 3** — [X-Ray tracing](docs/stage3.md) across the request path
- [x] **Stage 4** — [SLOs + alarms → SNS + a synthetics canary](docs/stage4.md)
- [x] **Stage 5** — [Incident-response runbook + a failure-injection drill](docs/stage5.md) (induce → alarm → runbook → recover)

**Future scope:** JSON logging, SLO burn-rate alerts, AWS FIS GameDays, anomaly detection, Slack/PagerDuty — see [docs/future-scope.md](docs/future-scope.md).

The headline evidence: **the dashboard mid-incident** — a metric spiking and the alarm red — then recovery.

## Cost

Mostly free tier: CloudWatch metrics/logs/dashboards, X-Ray, and SNS all have generous free tiers; the observed service is already running at ~$0. **Synthetics canaries** cost a little per run — keep the frequency low. A budget alarm guards the account.

---

Built by Rajolu Abheenash — [github.com/Abheenash](https://github.com/Abheenash)
