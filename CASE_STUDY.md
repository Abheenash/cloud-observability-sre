# Cloud Observability & Incident Response — Engineering Case Study

## Context

I run a small but real production service on AWS: **serverless-file-share**, a self-destructing file-sharing app live at `share.abheenash.com`. Its architecture is a serverless request path — **API Gateway (`sfs-api`) → Lambda (`sfs-issue-url` / `sfs-download` / `sfs-reaper`) → DynamoDB (`sfs-metadata`) + S3, encrypted with KMS**.

The service worked, but it was effectively opaque to operate. The only signals available were whatever infrastructure emitted by default — I couldn't answer "is it healthy right now?" at a glance, and I had no way to be told when it wasn't. Anyone can stand up a stack; far fewer can demonstrate they can *operate* one they've already shipped. This project closes that gap by adding a full observability and incident-response layer **on top of the already-running service** — genuine "run what you built," not a toy spun up to be watched. It's the third of a three-project arc: build securely (serverless-file-share), ship securely (secure-container-pipeline), and — here — **operate reliably**.

## My role

I designed and built the entire observability layer end to end, solo. That included instrumenting the live service, modeling the golden signals, defining SLOs and the alarm strategy, wiring notifications, standing up an outside-in canary and real-user monitoring, writing the incident runbook, and running a live failure-injection drill against production to prove the whole thing catches a real incident. Every piece of observability infrastructure is committed as Terraform in this repo.

## Problems identified

Before this project, the service was observable only in the narrowest infrastructure sense:

- **No customer-facing view of health.** Raw per-resource metrics existed, but nothing tied API Gateway, Lambda, and DynamoDB together into the four golden signals — latency, traffic, errors, saturation — so there was no single "is the service healthy?" answer.
- **No definition of "healthy."** There were no SLOs and no error budget, so there was no objective line between acceptable and degraded.
- **No alerting.** A failure would have been discovered by a user noticing, not by the system telling me. Nothing paged.
- **No outside-in signal.** Every available metric was self-reported by the service. If the front door was down, the service's own metrics might not even show it — there was no independent probe confirming the app was reachable from a real client's perspective.
- **Incident investigation was ad hoc.** Diagnosing an issue meant hand-writing log queries and manually reasoning across services under pressure — with no tracing to locate a slow segment and no written runbook to standardize the response.
- **The web/domain edge was unmeasured.** No visibility into real-user experience on the portfolio site or edge traffic.

The through-line: infra-only metrics answer "is this resource busy?" but not "are customers being served?" — and there was nothing to close that loop automatically.

## Architecture / implementation

The whole layer is Terraform and consumes the metrics, logs, and X-Ray traces the live stack emits (see [`docs/architecture.md`](docs/architecture.md)). The pieces:

- **Golden-signals dashboard** (`sfs-obs-golden-signals`, [`terraform/dashboard.tf`](terraform/dashboard.tf)) — one pane mapping the four signals across the stack: API Gateway traffic, 4xx/5xx errors, and p50/p95 latency; Lambda invocations, errors + throttles, and duration p95 across the three functions; DynamoDB throttled requests and request latency p95. It's the first thing I open in an incident.

- **SLO widget with error budget** — availability computed on the dashboard via metric math (`100*(1 - 5xx/requests)`) against a **99% availability** target drawn as an annotation, alongside a **p95 < 1500 ms** latency objective. The 99% target implies a 1%-of-requests error budget over 30 days; when it's burning, the runbook's policy is to freeze risky changes until it recovers.

- **Saved Logs Insights queries** ([`terraform/logs.tf`](terraform/logs.tf)) — pre-written investigations so an on-call responder isn't authoring queries mid-incident: `sfs-obs/lambda-errors` (surfaces exceptions / access-denied), `sfs-obs/lambda-slowest-invocations`, `sfs-obs/lambda-cold-starts`, and `sfs-obs/reaper-self-destructs`.

- **Distributed tracing (X-Ray)** — I enabled **active tracing** on the observed Lambdas (and granted their roles `AWSXRayDaemonWriteAccess`), then drove live traffic to populate the X-Ray service map and confirm the functions appear as traced services with real segments. This is the deeper diagnosis tool the runbook reaches for on the latency path — cold start vs. slow dependency. Enabling it is a reversible, one-time config change on the observed functions.

- **Symptom-vs-cause alarm strategy** ([`terraform/alarms.tf`](terraform/alarms.tf)) — `sfs-obs-api-5xx` (the customer-facing *symptom* — availability SLO at risk), `sfs-obs-api-latency-p95` (the latency SLO), and per-function `sfs-obs-<fn>-errors` alarms (the *cause* — which component is failing).

- **Composite service-health alarm → SNS** — `sfs-obs-service-health` is a composite that fires if **any** of the above trips, giving one "is it healthy?" page instead of alarm sprawl. All alarms route to the `sfs-obs-alerts` SNS topic → email ([`terraform/sns.tf`](terraform/sns.tf)), and every alarm maps to a step in the runbook.

- **Synthetics canary** (`sfs-uptime`, [`terraform/canary.tf`](terraform/canary.tf)) — a CloudWatch Synthetics canary that loads the live app and asserts a 2xx, providing outside-in uptime that's independent of the service's own metrics.

- **Real-user monitoring (RUM)** ([`terraform/rum.tf`](terraform/rum.tf), [`docs/web-monitoring.md`](docs/web-monitoring.md)) — a RUM app monitor (`abheenash-portfolio`) for `abheenash.com` collecting real sessions, page views, web-vitals, JS errors, and link clicks from actual visitors. The browser sends events through a least-privilege Cognito guest identity scoped to `rum:PutRumEvents` on that one monitor. A CloudFront row on the dashboard adds edge request volume and error rate for both distributions.

## Failure validation

Observability that's never been tested is a guess. I ran a live failure-injection drill against the production service to prove the loop actually closes ([`docs/stage5.md`](docs/stage5.md), [`docs/runbook.md`](docs/runbook.md)):

1. **Induce** — throttled `sfs-issue-url` to **zero reserved concurrency** (`aws lambda put-function-concurrency ... --reserved-concurrent-executions 0`).
2. **Impact** — `POST /files` immediately began returning **HTTP 503** to real users.
3. **Detect** — the `sfs-obs-api-5xx` alarm transitioned to **ALARM** (carrying the composite `sfs-obs-service-health` with it) and fired the SNS notification. Per the stage documentation, the alarm fired **within about 60 seconds** of the induced failure.
4. **Diagnose** — following the runbook's 5xx path, the dashboard showed a **throttle** spike rather than an errors spike, pointing straight at concurrency as the root cause.
5. **Recover** — restored concurrency (`aws lambda delete-function-concurrency`); `POST /files` returned to **HTTP 201** and the alarm cleared back to **OK**.

A complete **induce → detect → diagnose → recover** loop against a real service, with detection automated and the runbook resolving it in a single documented step.

## Operational result

The results are best stated qualitatively — the drill establishes the behavior, not a benchmark:

- **Customer-impacting failure is now caught automatically.** An induced outage that would previously have gone unnoticed until a user complained instead paged automatically, in the documented ~60-second window, via the symptom alarm.
- **Responders start from a consistent place.** The golden-signals dashboard, the composite health alarm, the saved queries, and the runbook give any responder the same first move — open the dashboard, read the golden signals, follow the mapped step — instead of improvising.
- **Signals distinguish symptom from cause.** The dashboard separated *what broke* (throttles) from the *customer symptom* (5xx), which is what let the runbook's throttling path resolve it directly.

## Trade-offs

- **Sensitivity vs. noise.** Alarm thresholds are deliberately tuned to page on genuinely customer-impacting conditions (e.g. API 5xx ≥ 3 in 5 min) rather than every transient blip. The composite alarm further collapses many possible triggers into one page to avoid alarm fatigue — at the cost of the page itself being less specific, which the runbook compensates for by directing you to the dashboard to localize.
- **Synthetic-check cost and cadence.** The canary is real recurring cost, unlike the mostly-free-tier metrics/logs/dashboards. I originally ran it every 5 minutes for tight outside-in coverage, then changed it to **hourly** — documented in `canary.tf` as roughly **$0.86/mo hourly vs. ~$10/mo at 5-minute**. For a hobby-scale app that's the right trade: I accept coarser outside-in resolution to keep the observability layer near-zero cost, backed by a budget alarm on the account.
- **Log fidelity.** Queries currently regex over text logs rather than filtering structured fields — good enough today, with structured JSON logging flagged as the next improvement.

## What I would improve next

From [`docs/future-scope.md`](docs/future-scope.md) — designs, not yet built:

- **Structured JSON logging** (via Powertools for AWS Lambda) so Logs Insights filters on real fields (fileId, latency, outcome) instead of regex over text.
- **Composite SLO burn-rate alerts** — multi-window, multi-burn-rate alerting (fast-burn + slow-burn), the Google SRE workbook pattern, replacing single static thresholds.
- **AWS FIS experiments** — replace the manual throttle drill with Fault Injection Simulator templates (inject latency, throttle, deny IAM) run on a schedule as GameDays.
- **Anomaly detection** — CloudWatch anomaly-detection bands on latency/traffic instead of static thresholds.
- **Deeper tracing** — instrument the Lambdas with the X-Ray SDK for per-dependency subsegments (DynamoDB/S3/KMS timings), beyond the invocation segment.
- **Dashboards as sharable JSON + Amazon Managed Grafana**, and **alerting to Slack/PagerDuty** (SNS → Chatbot/Lambda) with on-call routing.
- **Cost observability** — a budget + cost-anomaly dashboard alongside the reliability one.

## Evidence

- Observability infrastructure as code — [`terraform/`](terraform/): dashboard ([`dashboard.tf`](terraform/dashboard.tf)), alarms + composite ([`alarms.tf`](terraform/alarms.tf)), saved queries ([`logs.tf`](terraform/logs.tf)), canary ([`canary.tf`](terraform/canary.tf)), SNS ([`sns.tf`](terraform/sns.tf)), RUM ([`rum.tf`](terraform/rum.tf)).
- Incident runbook — [`docs/runbook.md`](docs/runbook.md) (alarm → action mapping, SLOs, error-budget policy).
- Failure-injection drill — [`docs/stage5.md`](docs/stage5.md) (induce → detect → diagnose → recover).
- Architecture — [`docs/architecture.md`](docs/architecture.md); web/domain monitoring — [`docs/web-monitoring.md`](docs/web-monitoring.md).
- Stage write-ups — [`docs/stage1.md`](docs/stage1.md) … [`docs/stage5.md`](docs/stage5.md).
- Dashboard: CloudWatch dashboard `sfs-obs-golden-signals`; composite alarm `sfs-obs-service-health`; canary `sfs-uptime`.
- The live probed service — **https://share.abheenash.com** (canary target).
