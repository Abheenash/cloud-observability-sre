# Anomaly-detection alarms: CloudWatch learns the metric's daily/weekly shape and
# alarms when it leaves the band — so a latency regression at 3 am and a traffic
# collapse (the front door is down but nothing is erroring) both page, without a
# hand-tuned static threshold for each.

resource "aws_cloudwatch_metric_alarm" "latency_anomaly" {
  alarm_name          = "${var.name_prefix}-api-latency-anomaly"
  alarm_description   = "API p95 latency outside its learned band (2 std dev)"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold_metric_id = "band"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(p95, 2)"
    label       = "expected p95 latency"
    return_data = true
  }
  metric_query {
    id          = "p95"
    return_data = true
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Latency"
      dimensions  = { ApiId = var.api_id }
      period      = 300
      stat        = "p95"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "traffic_anomaly" {
  alarm_name          = "${var.name_prefix}-api-traffic-drop"
  alarm_description   = "Request volume fell below its learned band — the front door may be down"
  comparison_operator = "LessThanLowerThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold_metric_id = "band"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(reqs, 2)"
    label       = "expected requests"
    return_data = true
  }
  metric_query {
    id          = "reqs"
    return_data = true
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      dimensions  = { ApiId = var.api_id }
      period      = 900
      stat        = "Sum"
    }
  }
}
