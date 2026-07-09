# Future scope

Planned enhancements beyond the shipped Stages 0–5. Designs, not yet built.

| Idea | Notes |
|---|---|
| **Structured JSON logging** | Emit JSON logs from the observed Lambdas (via Powertools for AWS Lambda) so Logs Insights can filter on real fields (fileId, latency, outcome) instead of regex over text. |
| **Composite SLO burn-rate alerts** | Multi-window, multi-burn-rate alerting (fast-burn + slow-burn) instead of a single threshold — the Google SRE workbook pattern. |
| **AWS FIS experiments** | Replace the manual throttle drill with **AWS Fault Injection Simulator** experiment templates (inject latency, throttle, deny IAM) run on a schedule as GameDays. |
| **Anomaly detection** | CloudWatch anomaly-detection bands on latency/traffic instead of static thresholds. |
| **Distributed tracing depth** | Instrument the Lambdas with the X-Ray SDK for subsegments (DynamoDB/S3/KMS timings) — not just the invocation segment. |
| **Dashboards as sharable JSON + Grafana** | Export the dashboard and stand up an Amazon Managed Grafana view for a multi-service pane. |
| **Alerting to Slack/PagerDuty** | SNS → Chatbot/Lambda → Slack, with on-call routing. |
| **RUM** | CloudWatch RUM on the web UI for real-user latency/error signals from the browser. |
| **Cost observability** | A budget + cost-anomaly dashboard alongside the reliability one. |
