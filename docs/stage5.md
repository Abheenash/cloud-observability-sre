# Stage 5 — incident runbook + failure-injection drill

**Goal:** prove the observability actually works — induce a real failure on the live
service, watch it get detected, and recover using the runbook.

## The drill (run live against serverless-file-share)

1. **Induce** — throttle the `sfs-issue-url` Lambda to **zero reserved concurrency**:
   ```
   aws lambda put-function-concurrency --function-name sfs-issue-url --reserved-concurrent-executions 0
   ```
2. **Impact** — `POST /files` immediately started returning **HTTP 503** to real users.
3. **Detect** — the `sfs-obs-api-5xx` alarm transitioned to **`ALARM`** (and the composite `sfs-obs-service-health` with it), firing the SNS notification. **Detection confirmed.**
4. **Diagnose** — the [runbook](runbook.md) "5xx" path: dashboard showed a **throttle** spike (not errors), pointing straight at concurrency.
5. **Recover** — restore concurrency:
   ```
   aws lambda delete-function-concurrency --function-name sfs-issue-url
   ```
   `POST /files` returned to **HTTP 201**; the alarm cleared back to **OK**.

## Result

```
induce (throttle → 0)   -> API 503   (incident live)
alarm sfs-obs-api-5xx    -> ALARM     (detected automatically)
recover (restore)        -> API 201   (service healthy)
alarm                    -> OK        (resolved)
```

A complete **induce → detect → diagnose → recover** loop against a real production
service — the thing that separates "I can build it" from "I can operate it."

## Evidence

The dashboard and alarms are private to the AWS account — see [screenshots](screenshots/)
(dashboard mid-incident, the `service-health` alarm firing, and recovery to OK).

## What Stage 5 ties together

- **Golden-signals dashboard** (Stage 2) showed *what* broke (throttles, not errors).
- **Alarms + SNS** (Stage 4) did the detecting and paging.
- **The runbook** turned the alarm into a fix in one step.
- **X-Ray** (Stage 3) and **Logs Insights** (Stage 1) are the deeper-diagnosis tools when the cause isn't obvious from the dashboard.
