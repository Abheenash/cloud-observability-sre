# Stage 4 — alarms that map to the SLOs and golden signals, wired to SNS.

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "API Gateway 5xx errors — availability SLO at risk"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "${var.name_prefix}-api-latency-p95"
  alarm_description   = "API p95 latency over the ${var.slo_p95_latency_ms}ms SLO"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = var.api_id }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.slo_p95_latency_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = toset(var.lambda_functions)
  alarm_name          = "${var.name_prefix}-${each.value}-errors"
  alarm_description   = "${each.value} Lambda is erroring"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# One "is the service healthy?" signal — any golden-signal breach pages once.
resource "aws_cloudwatch_composite_alarm" "service_health" {
  alarm_name        = "${var.name_prefix}-service-health"
  alarm_description = "Any golden-signal breach on serverless-file-share"
  alarm_rule = join(" OR ", concat(
    [
      "ALARM(${aws_cloudwatch_metric_alarm.api_5xx.alarm_name})",
      "ALARM(${aws_cloudwatch_metric_alarm.api_latency_p95.alarm_name})"
    ],
    [for f in var.lambda_functions : "ALARM(${aws_cloudwatch_metric_alarm.lambda_errors[f].alarm_name})"]
  ))
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
