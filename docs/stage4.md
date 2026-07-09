# Stage 4 — SLOs, alarms, and a synthetics canary

**Goal:** define what "healthy" means, alert when it isn't, and probe from outside.

## SLOs

- **Availability:** 99% (tracked on the dashboard's SLO widget; error budget = 1% / 30 days).
- **Latency:** p95 < 1500 ms.

## Alarms → SNS ([`terraform/alarms.tf`](../terraform/alarms.tf))

| Alarm | Fires when |
|---|---|
| `sfs-obs-api-5xx` | API 5xx ≥ 3 in 5 min (availability SLO at risk) |
| `sfs-obs-api-latency-p95` | API p95 latency over the 1500 ms SLO |
| `sfs-obs-<fn>-errors` | any observed Lambda errors |
| `sfs-obs-service-health` | **composite** — ANY of the above; one "is it healthy?" signal |

All wire to the `sfs-obs-alerts` SNS topic (→ email). Each maps to a [runbook](runbook.md) step.

## Synthetics canary ([`terraform/canary.tf`](../terraform/canary.tf))

`sfs-uptime` — a CloudWatch Synthetics canary that loads the live app every 5 minutes and
asserts a 2xx, giving **outside-in** uptime independent of the service's own metrics.

Proven in the [Stage 5 drill](stage5.md): the `api-5xx` alarm fired within ~60s of an induced
failure and cleared on recovery.
