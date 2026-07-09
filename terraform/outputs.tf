output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "service_health_alarm" {
  value = aws_cloudwatch_composite_alarm.service_health.alarm_name
}

output "canary_name" {
  value = aws_synthetics_canary.uptime.name
}

output "rum_app_monitor_id" {
  description = "App monitor UUID — goes in the RUM web snippet."
  value       = aws_rum_app_monitor.portfolio.app_monitor_id
}

output "rum_identity_pool_id" {
  value = aws_cognito_identity_pool.rum.id
}
