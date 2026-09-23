# Cloud Observability & Incident Response — operating a live serverless service on AWS

> **Sep 2026 (v4):** **Splunk HEC forwarding** — a CloudWatch Logs subscription filter into a Lambda that speaks HEC, with the four things that silently break one (ms vs s timestamps, JSON array vs concatenated objects, CONTROL_MESSAGE forwarded as data, a plaintext endpoint leaking the bearer token) each pinned by a test. Off by default; 9 unit tests, 5 terraform tests.
>
> **Sep 2026 (v3):** README now leads with the **measured drill** (105 s detection, 297 s recovery) instead of two screenshots that were never captured; AWS provider 5 → **6**; Renovate + pre-commit + tflint.
>
> **Sep 2026:** multi-window burn-rate SLO alarms, anomaly-detection alarms, an AWS FIS GameDay experiment with the health alarm as its stop condition, an automated drill measured at 105 s detection, CI.

Take a **real, running production service** — my [serverless-file-share](https://github.com/Abheenash/serverless-file-share) app (live at `share.abheenash.com`) — and make it **observable and operable**: golden-signal dashboards, distributed tracing, SLOs with error budgets, automated alerting, and a documented incident-response runbook — capped by a demo that induces a real failure, catches it, and recovers.

**Status:** ✅ All stages complete — observing the **live** serverless-file-share stack; an induced incident was detected and recovered ([docs/stage5.md](docs/stage5.md)). See the [architecture](docs/architecture.md) and [runbook](docs/runbook.md).

## The headline evidence — a measured drill

The most recent automated drill ([`docs/drills/`](docs/drills/), written by `scripts/drill.sh`):

| | |
|---|---|
| Induced fault | `sfs-issue-url` throttled to 0 reserved concurrency |
| Alarm watched | `sfs-obs-service-health` (composite: api-5xx + p95 latency + per-function errors) |
| **Detection time** | **105 s** (induce → ALARM) |
| Time to clear | 297 s (restore → OK) |
| Probe during / after | HTTP 503 → HTTP 201 |

Reproducible on demand: `scripts/drill.sh` restores from a `trap`, so Ctrl-C can't leave the
service throttled. The dashboard and alarms themselves live in a private AWS account —
[`docs/screenshots/`](docs/screenshots/) carries the capture guide and the exact commands to
recreate the incident state.

## v2 (Sep 2026) — the roadmap items, built and measured

| Item | What shipped | Evidence |
| --- | --- | --- |
| **Multi-window, multi-burn-rate SLO alerts** (`terraform/burn_rate.tf`) | Four metric-math error-ratio alarms (1 h / 5 m at 14.4× budget, 6 h / 30 m at 6×) combined into **`slo-burn-fast`** (page) and **`slo-burn-slow`** (ticket). The short window confirms the burn is still happening, so a page never fires for an incident that already ended. | live in the account alongside the Stage-4 alarms |
| **Anomaly detection** (`terraform/anomaly.tf`) | p95 latency outside a learned 2-σ band, and a **traffic-drop** alarm for "the front door is down but nothing is erroring". | live |
| **AWS Fault Injection Service GameDay** (`terraform/fis.tf`, `fis/throttle-lambda.yaml`) | The Stage-5 drill as an FIS experiment: an SSM Automation runbook throttles `sfs-issue-url` to 0 for a window, with `onFailure`/`onCancel` both wired to *restore*. The experiment's **stop condition is the composite service-health alarm** — detection aborts the experiment, which restores production. One run answers "does the alarm catch it?" and "how fast?", and cannot leave the service throttled. IAM: the automation role can change concurrency on the three observed functions and nothing else. | template `EXTBHv4TnhPwLECcG` |
| **Automated, measured drill** (`scripts/drill.sh`) | Throttles, generates real traffic, polls the alarm every 5 s, restores from a `trap` (Ctrl-C can't leave it throttled), and writes a report. | [`docs/drills/`](docs/drills/) |
| **CI** | `terraform fmt`/`validate`, checkov against a reviewed baseline, the SSM runbook's safety invariants asserted (every step falls through to *restore*), `bash -n` on the drill. | badge above |

**Measured drill, 2026-09-19** ([report](docs/drills/)): induce → `service-health` **ALARM in 105 s** (the 5xx alarm evaluates a 300 s period, so detection lands between ~60 s and ~5 min depending on where in the window the failure starts — the Stage-5 write-up's "~60 s" was the lucky end of that range); restore → OK in 297 s (one clean period). Probe: HTTP 503 during, 201 after.

Still designs: structured JSON logging lives in the observed service's repo; Slack/PagerDuty routing and Managed Grafana remain on the list.

## Why this project

Projects that *build* things are common; projects that prove you can *operate* them in production are rare — that's the gap this fills. It's the third of a three-project arc:

- **[serverless-file-share](https://github.com/Abheenash/serverless-file-share)** — *build securely*
- **[secure-container-pipeline](https://github.com/Abheenash/secure-container-pipeline)** — *ship securely*
- **this** — *operate reliably*

The service under observation is **already live**, so this is genuine "run what you built" — not a toy spun up to be watched.

## What is observed

The serverless-file-share stack: **API Gateway → Lambda (issue-url / download / reaper) → S3 + DynamoDB**, encrypted with KMS.

Plus the **domain and portfolio site** (`abheenash.com`) — real-user monitoring (visitors, page views, web-vitals, JS errors, link clicks) via **CloudWatch RUM**, and edge traffic via **CloudFront** metrics. See [docs/web-monitoring.md](docs/web-monitoring.md).

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

## How it works

1. The live service emits **structured logs**, **custom + built-in metrics**, and **X-Ray traces** (active tracing enabled on the Lambdas + API Gateway).
2. **CloudWatch** aggregates them into a **golden-signals dashboard** — latency, traffic, errors, saturation — for API Gateway, Lambda, and DynamoDB.
3. **SLOs** (e.g. 99% availability, a p95-latency target) are tracked with an **error budget**; alarms fire on breach and on golden-signal thresholds.
4. A **CloudWatch Synthetics canary** (`terraform/canary.tf`) gives outside-in uptime by loading the live app and asserting a 2xx — independent of the service's own metrics. It is the one component with a real recurring cost, so it is run **build → prove → destroy**: `terraform apply` stands it up on demand for a demo, then it is torn down (see [Cost](#cost)).
5. Alarms notify via **SNS → email**, and each maps to a step in the **runbook**.
6. Capstone: **induce a failure** (throttle the issue-url Lambda to zero concurrency so uploads return 5xx), watch the dashboard + alarm catch it, follow the runbook, and recover.

## Services and why

| Service | Role here |
|---|---|
| CloudWatch (Logs, Metrics, Dashboards, Alarms) | Core observability + alerting |
| CloudWatch Logs Insights | Query structured Lambda logs |
| X-Ray | Distributed tracing across API Gateway → Lambda → DynamoDB |
| CloudWatch Synthetics | Outside-in uptime canary against the live API (IaC; run on-demand for cost) |
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

Mostly free tier: CloudWatch metrics/logs/dashboards, X-Ray, and SNS all have generous free tiers, and the observed service already runs at ~$0. The one exception is the **Synthetics canary**, which bills per run (~$0.86/mo hourly). To keep the whole observability layer at $0 at rest, the canary follows a **build → prove → destroy** loop — the same cost-controlled model as [aws-eks-platform](https://github.com/Abheenash/aws-eks-platform): `terraform apply` stands it up on demand for a demo, then it is torn down again. It is currently torn down; the dashboard, alarms, X-Ray, and RUM stay live. A budget alarm guards the account.

---

Built by Rajolu Abheenash — [github.com/Abheenash](https://github.com/Abheenash)
