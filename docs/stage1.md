# Stage 1 — structured logging + Logs Insights

**Goal:** turn the observed Lambdas' raw logs into one-click investigations.

The serverless-file-share Lambdas already ship logs to CloudWatch (`/aws/lambda/sfs-*`).
This stage adds **saved CloudWatch Logs Insights queries** ([`terraform/logs.tf`](../terraform/logs.tf)) so an on-call engineer doesn't write queries during an incident:

| Saved query | Answers |
|---|---|
| `sfs-obs/lambda-errors` | Which invocations errored, and why (error/exception/access-denied)? |
| `sfs-obs/lambda-slowest-invocations` | What were the slowest requests (from the REPORT lines)? |
| `sfs-obs/lambda-cold-starts` | Which invocations paid a cold-start `initDuration`? |
| `sfs-obs/reaper-self-destructs` | Which files did the reaper actually delete? |

These are the first diagnostic step the [runbook](runbook.md) points to.

*(Future: emit JSON logs via Lambda Powertools so queries filter on real fields — see [future-scope.md](future-scope.md).)*
