# Stage 2 — golden-signals dashboard for the observed serverless stack.
# Latency · Traffic · Errors · Saturation, across API Gateway / Lambda / DynamoDB.

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-golden-signals"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "text", x = 0, y = 0, width = 24, height = 1,
        properties = { markdown = "## serverless-file-share — golden signals   ·   API Gateway · Lambda · DynamoDB" }
      },

      # ---------- API Gateway (the front door) ----------
      {
        type = "metric", x = 0, y = 1, width = 8, height = 6,
        properties = {
          title   = "API — Traffic (req/min)", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
          metrics = [["AWS/ApiGateway", "Count", "ApiId", var.api_id]]
        }
      },
      {
        type = "metric", x = 8, y = 1, width = 8, height = 6,
        properties = {
          title = "API — Errors (4xx / 5xx)", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_id],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id]
          ]
        }
      },
      {
        type = "metric", x = 16, y = 1, width = 8, height = 6,
        properties = {
          title = "API — Latency (ms)", region = var.region, period = 60, view = "timeSeries",
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p50", label = "p50" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p95", label = "p95" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiId", var.api_id, { stat = "p95", label = "integration p95" }]
          ]
        }
      },

      # ---------- Lambda (the compute) ----------
      {
        type = "metric", x = 0, y = 7, width = 8, height = 6,
        properties = {
          title   = "Lambda — Invocations", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
          metrics = [for f in var.lambda_functions : ["AWS/Lambda", "Invocations", "FunctionName", f]]
        }
      },
      {
        type = "metric", x = 8, y = 7, width = 8, height = 6,
        properties = {
          title = "Lambda — Errors + Throttles", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
          metrics = concat(
            [for f in var.lambda_functions : ["AWS/Lambda", "Errors", "FunctionName", f]],
            [for f in var.lambda_functions : ["AWS/Lambda", "Throttles", "FunctionName", f, { label = "${f} throttles" }]]
          )
        }
      },
      {
        type = "metric", x = 16, y = 7, width = 8, height = 6,
        properties = {
          title   = "Lambda — Duration p95 (ms)", region = var.region, period = 60, stat = "p95", view = "timeSeries",
          metrics = [for f in var.lambda_functions : ["AWS/Lambda", "Duration", "FunctionName", f]]
        }
      },

      # ---------- DynamoDB (the data) ----------
      {
        type = "metric", x = 0, y = 13, width = 12, height = 6,
        properties = {
          title = "DynamoDB — Throttled requests", region = var.region, period = 60, stat = "Sum", view = "timeSeries",
          metrics = [
            ["AWS/DynamoDB", "ThrottledRequests", "TableName", var.dynamodb_table]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 13, width = 12, height = 6,
        properties = {
          title = "DynamoDB — Latency p95 (ms)", region = var.region, period = 60, stat = "p95", view = "timeSeries",
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.dynamodb_table, "Operation", "PutItem"],
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.dynamodb_table, "Operation", "GetItem"]
          ]
        }
      },

      # ---------- SLO ----------
      {
        type = "metric", x = 0, y = 19, width = 24, height = 6,
        properties = {
          title  = "SLO — API availability %  (target ${var.slo_availability_pct}%)",
          region = var.region, period = 300, view = "timeSeries",
          metrics = [
            [{ expression = "100*(1-(m2/(m1+0.0001)))", label = "Availability %", id = "e1" }],
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id, { id = "m1", visible = false }],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id, { id = "m2", visible = false }]
          ],
          yAxis       = { left = { min = 90, max = 100 } },
          annotations = { horizontal = [{ label = "SLO", value = var.slo_availability_pct }] }
        }
      }
    ]
  })
}
