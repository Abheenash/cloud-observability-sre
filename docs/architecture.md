# Architecture

```mermaid
flowchart TB
    subgraph observed[Observed service — serverless-file-share LIVE]
        api[API Gateway] --> lam[Lambdas<br/>issue-url · download · reaper]
        lam --> ddb[(DynamoDB)]
        lam --> s3[(S3 + KMS)]
    end

    api -. metrics .-> cw
    lam -. metrics + logs .-> cw
    ddb -. metrics .-> cw
    lam -. X-Ray traces .-> xray[X-Ray<br/>service map + traces]

    subgraph obs[Observability — this project, all Terraform]
        cw[CloudWatch<br/>golden-signals dashboard<br/>Logs Insights queries]
        alarms[Alarms<br/>5xx · p95 latency · Lambda errors<br/>composite service-health]
        canary[Synthetics canary<br/>outside-in uptime]
    end

    canary -->|probe| api
    cw --> alarms
    canary --> alarms
    alarms -->|breach| sns[SNS] --> email([email])
    alarms -.-> runbook[[runbook.md]]

    classDef store fill:#1a3a5c,stroke:#5b8cff,color:#fff
    class ddb,s3 store
```

## The four golden signals, mapped

| Signal | Where |
|---|---|
| **Latency** | API p50/p95 + Lambda Duration p95 + DynamoDB latency |
| **Traffic** | API request count, Lambda invocations |
| **Errors** | API 4xx/5xx, Lambda errors, DynamoDB throttles |
| **Saturation** | Lambda throttles + concurrent executions |

## Flow

The live serverless stack emits metrics, logs, and X-Ray traces. This project (all Terraform) turns them into a **golden-signals dashboard**, **saved Logs Insights queries**, **SLO-backed alarms** (wired to SNS), and an **outside-in Synthetics canary** — with every alarm mapped to a step in the [runbook](runbook.md). The capstone is a rehearsed failure-injection drill ([stage5.md](stage5.md)).
