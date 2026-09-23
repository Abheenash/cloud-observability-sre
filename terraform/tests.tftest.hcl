mock_provider "aws" {
  # The mock generates a random account id, which the provider then rejects as an
  # invalid ARN component. A real-shaped one lets the ARN assertions run.
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111122223333" }
  }
  override_data {
    target = data.aws_iam_policy_document.splunk_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.splunk_forwarder[0]
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
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

run "splunk_forwarding_is_off_by_default" {
  command = plan

  # There is no Splunk in this account. A forwarder pointing nowhere would retry,
  # fail, and fill a DLQ — so the default must create nothing at all.
  assert {
    condition     = length(aws_lambda_function.splunk_forwarder) == 0
    error_message = "With splunk_hec_url empty, the forwarder must not be created."
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.to_splunk) == 0
    error_message = "No subscription filters without a destination to send to."
  }
}

run "rejects_a_plaintext_hec_endpoint" {
  command = plan

  variables {
    splunk_hec_url = "http://splunk.example.invalid/services/collector"
  }

  # The HEC token is a bearer credential; over http it is on the wire in clear.
  expect_failures = [var.splunk_hec_url]
}

run "enabled_forwarder_filters_to_the_apps_own_log_lines" {
  command = plan

  variables {
    splunk_hec_url = "https://http-inputs-example.splunkcloud.com/services/collector"
  }

  assert {
    condition     = length(aws_lambda_function.splunk_forwarder) == 1
    error_message = "A configured endpoint must create the forwarder."
  }

  # An empty filter_pattern ships START/END/REPORT for every invocation too —
  # roughly triple the volume, and Splunk is licensed per GB ingested per day.
  assert {
    condition = alltrue([
      for f in aws_cloudwatch_log_subscription_filter.to_splunk : f.filter_pattern != ""
    ])
    error_message = "Subscription filters must narrow to the app's structured lines, not ship every Lambda REPORT line."
  }

  assert {
    condition     = aws_ssm_parameter.splunk_hec_token[0].type == "SecureString"
    error_message = "The HEC token must be a SecureString, never a plain parameter or an env var."
  }
}
