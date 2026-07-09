# Stage 2 — golden-signals dashboard

**Goal:** one dashboard that answers "is the service healthy?" at a glance.

[`terraform/dashboard.tf`](../terraform/dashboard.tf) builds a CloudWatch dashboard
(`sfs-obs-golden-signals`) covering the **four golden signals** across the stack:

- **API Gateway** — traffic (req/min), 4xx/5xx errors, latency p50/p95 (+ integration latency).
- **Lambda** (issue-url / download / reaper) — invocations, errors + throttles, duration p95.
- **DynamoDB** — throttled requests, request latency p95.
- **SLO widget** — availability % via metric math `100*(1 - 5xx/requests)`, with the 99% target drawn as an annotation.

The dashboard is what you open first during an incident — in the [Stage 5 drill](stage5.md)
it showed a *throttle* spike (not errors), which pointed straight at the root cause.
