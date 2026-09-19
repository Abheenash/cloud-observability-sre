# Multi-window, multi-burn-rate SLO alerting (Google SRE Workbook, ch. 5).
#
# A single "5xx >= 3 in 5 minutes" threshold pages on a blip and sleeps through a
# slow leak. Burn rate = (observed error ratio) / (error budget). For a 99% SLO the
# budget is 1%, so:
#   fast burn  — 14.4x budget over 1 h  AND over the last 5 min  (2% of the 30-day budget in 1 h)
#   slow burn  —    6x budget over 6 h  AND over the last 30 min (5% of the budget in 6 h)
# The short window confirms the burn is still happening, so a page never fires for
# an incident that already ended. Each window is a metric-math alarm; the pairs are
# combined with composite alarms.

locals {
  error_budget = (100 - var.slo_availability_pct) / 100 # 0.01 for a 99% SLO
  burn_windows = {
    fast_long  = { period = 3600, burn = 14.4 }
    fast_short = { period = 300, burn = 14.4 }
    slow_long  = { period = 21600, burn = 6 }
    slow_short = { period = 1800, burn = 6 }
  }
}

resource "aws_cloudwatch_metric_alarm" "burn" {
  for_each            = local.burn_windows
  alarm_name          = "${var.name_prefix}-burn-${replace(each.key, "_", "-")}"
  alarm_description   = "Error ratio > ${each.value.burn}x the error budget over ${each.value.period}s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = each.value.burn * local.error_budget
  treat_missing_data  = "notBreaching"

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "5xx"
      dimensions  = { ApiId = var.api_id }
      period      = each.value.period
      stat        = "Sum"
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      dimensions  = { ApiId = var.api_id }
      period      = each.value.period
      stat        = "Sum"
    }
  }
  metric_query {
    id          = "ratio"
    expression  = "IF(requests > 0, errors / requests, 0)"
    label       = "error ratio"
    return_data = true
  }
}

resource "aws_cloudwatch_composite_alarm" "burn_fast" {
  alarm_name        = "${var.name_prefix}-slo-burn-fast"
  alarm_description = "Fast burn: 14.4x budget over 1h AND 5m — page now"
  alarm_rule        = "ALARM(${aws_cloudwatch_metric_alarm.burn["fast_long"].alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.burn["fast_short"].alarm_name})"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_composite_alarm" "burn_slow" {
  alarm_name        = "${var.name_prefix}-slo-burn-slow"
  alarm_description = "Slow burn: 6x budget over 6h AND 30m — ticket, not a page"
  alarm_rule        = "ALARM(${aws_cloudwatch_metric_alarm.burn["slow_long"].alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.burn["slow_short"].alarm_name})"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]
}
