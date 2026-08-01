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

## Operating the Synthetics canary (on-demand)
The `sfs-uptime` canary is the one component with a real recurring cost (~$0.86/mo hourly), so it is run **build → prove → destroy** rather than left running: provisioned as Terraform, stood up on demand for a demo, then torn down so the observability layer sits at $0 at rest. The rest of the layer (dashboard, alarms, X-Ray, RUM) stays live. Its `terraform/canary.tf` config is intact, so it is always one command away.

**Before a demo — stand it up** (from `terraform/`; the `-target` pulls in the bucket + IAM role it depends on):
```
terraform apply -target=aws_synthetics_canary.uptime
```
`start_canary = true`, so it begins probing `share.abheenash.com` hourly immediately. Allow one run (or trigger `aws synthetics start-canary --name sfs-uptime`) before expecting the uptime widget to populate.

**After the demo — tear it back down** (the bucket is `force_destroy = true`, so its artifacts are removed automatically):
```
terraform destroy \
  -target=aws_synthetics_canary.uptime \
  -target=aws_iam_role_policy.canary \
  -target=aws_iam_role.canary \
  -target=aws_s3_bucket_public_access_block.canary \
  -target=aws_s3_bucket.canary
```
This leaves every other observed signal untouched. Verify with `aws synthetics describe-canaries --query 'Canaries[].Name'` (should not list `sfs-uptime`).

## Verified failure-injection drill
See [stage5.md](stage5.md): throttling `sfs-issue-url` to zero concurrency induces API 5xx → the alarm fires → restoring concurrency recovers the service. This runbook's "Throttling" path is the one that resolves it.
