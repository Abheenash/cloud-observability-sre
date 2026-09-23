mock_provider "aws" {
  # Mocked data sources return placeholder strings that the AWS provider then
  # rejects as invalid JSON; a minimal valid document keeps the mock usable.
  override_data {
    target = data.aws_iam_policy_document.automation
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.canary
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.canary_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.fis
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.fis_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.rum_guest_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.ssm_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "archive" {}
run "composite_health_alarm_has_an_action" {
  command = plan

  # An alarm with no action is a dashboard decoration. The whole point of the
  # composite is that it is the single thing that pages.
  assert {
    condition     = length(aws_cloudwatch_composite_alarm.service_health.alarm_actions) > 0
    error_message = "The composite service-health alarm must notify something. An alarm nobody is told about does not shorten an incident."
  }
}

run "silence_is_caught_by_a_traffic_alarm_not_by_the_error_alarms" {
  command = plan

  # I initially asserted that no alarm may use treat_missing_data =
  # "notBreaching". That was wrong, and worth recording rather than quietly
  # deleting.
  #
  # These are error-COUNT alarms (Sum of 5xx, Sum of Errors). For a low-traffic
  # serverless app, missing data means "nobody called it", which is normal —
  # "breaching" would page every quiet night and the alarm would be muted within
  # a week. notBreaching is correct here.
  #
  # The failure mode that actually worries me — the front door is down, so there
  # are no requests AND no errors — is not an error-alarm problem at all. It needs
  # a separate alarm on request VOLUME, which is what api-traffic-drop is. So the
  # invariant worth enforcing is that this alarm continues to exist: without it,
  # notBreaching on the error alarms really would hide an outage.
  assert {
    condition     = aws_cloudwatch_metric_alarm.traffic_anomaly.comparison_operator == "LessThanLowerThreshold"
    error_message = "The traffic-drop alarm must fire when volume falls BELOW its learned band. It is the only thing watching for silence; the error-count alarms deliberately cannot."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.traffic_anomaly.alarm_actions) > 0
    error_message = "The traffic-drop alarm must notify — it is the compensating control that makes notBreaching safe on the error alarms."
  }
}
