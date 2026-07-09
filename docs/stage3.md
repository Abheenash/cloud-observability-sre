# Stage 3 — distributed tracing (X-Ray)

**Goal:** trace a request across the stack to locate bottlenecks.

**Active tracing** was enabled on the observed Lambdas (and `AWSXRayDaemonWriteAccess`
granted to their roles) so X-Ray records each invocation as a traced segment:

```
aws lambda update-function-configuration --function-name sfs-issue-url --tracing-config Mode=Active
```

Driving traffic through the live API then populated the **X-Ray service map** — verified
that `sfs-issue-url` and `sfs-download` appear as traced services with real segments.

**Enabling tracing on the observed service is a one-time config change on #1's functions**
(reversible with `--tracing-config Mode=PassThrough`). It's the deeper-diagnosis tool the
[runbook](runbook.md) reaches for on the latency path — e.g. a cold start vs. a slow DynamoDB
call.

*(Future: instrument the app with the X-Ray SDK for per-dependency subsegments — see [future-scope.md](future-scope.md).)*
