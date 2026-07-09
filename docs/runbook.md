# Incident runbook — serverless-file-share

Every alarm maps to a first diagnostic step and a remediation. Alarms notify
`sfs-obs-alerts` (SNS → email).

## Alarm → action

### `sfs-obs-service-health` (composite) or `sfs-obs-api-5xx`
**Symptom:** the API is returning 5xx / users can't upload or download.
1. Open the **golden-signals dashboard** — is it errors, latency, or throttles?
2. Check **Lambda — Errors + Throttles**: a spike in *Errors* → a function is failing; a spike in *Throttles* → concurrency limit hit.
3. If errors: run the saved **`sfs-obs/lambda-errors`** Logs Insights query to see the exception.
4. Common causes + fixes:
   - **Throttling** (reserved concurrency too low / hit account limit) → `aws lambda delete-function-concurrency --function-name <fn>` or raise the limit.
   - **AccessDenied** in logs (IAM/KMS drift) → restore the function's role policy.
   - **Bad deploy** → roll back the function version.
5. Confirm recovery: 5xx returns to zero and the alarm returns to **OK**.

### `sfs-obs-api-latency-p95`
**Symptom:** p95 latency over the 1500 ms SLO.
1. **X-Ray → service map / traces** — find the slow segment (Lambda cold start? DynamoDB? S3?).
2. Check **`sfs-obs/lambda-cold-starts`** — a burst of cold starts inflates p95.
3. Check **DynamoDB — Latency p95**; if high, inspect capacity/throttling.
4. Remediate: provisioned concurrency for cold starts, or address the slow dependency.

### `sfs-obs-<function>-errors`
**Symptom:** a specific Lambda (`issue-url` / `download` / `reaper`) is erroring.
1. Run **`sfs-obs/lambda-errors`** filtered to that function's log group.
2. `reaper` errors → files may not be self-destructing; check the DynamoDB-stream DLQ (`sfs-reaper-dlq`).
3. Fix the root cause; confirm the error rate returns to zero.

## SLOs & error budget
- **Availability:** 99% (tracked on the dashboard's SLO widget). Error budget = 1% of requests / 30 days.
- **Latency:** p95 < 1500 ms.
- When the error budget is being burned, freeze risky changes until it recovers.

## Verified failure-injection drill
See [stage5.md](stage5.md): throttling `sfs-issue-url` to zero concurrency induces API 5xx → the alarm fires → restoring concurrency recovers the service. This runbook's "Throttling" path is the one that resolves it.
