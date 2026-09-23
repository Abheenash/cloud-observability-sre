mock_provider "datadog" {}

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

run "datadog_is_off_by_default" {
  command = plan

  # There is no Datadog org behind this account. Monitors pointing at one that
  # does not exist would simply fail to create.
  assert {
    condition     = length(datadog_monitor.error_rate) == 0 && length(datadog_dashboard.golden_signals) == 0
    error_message = "With datadog_api_key empty, no Datadog resources may be created."
  }
}

run "datadog_monitors_treat_missing_data_the_same_way_the_cloudwatch_alarms_do" {
  command = plan

  variables {
    datadog_api_key = "0123456789abcdef0123456789abcdef"
    datadog_app_key = "0123456789abcdef0123456789abcdef01234567"
  }

  # The error-ratio monitor must NOT alert on no-data: no requests means no
  # errors, which is a quiet night. This is the same reasoning as notBreaching
  # on the CloudWatch error alarms, and it is only safe because of the
  # traffic-drop monitor below.
  assert {
    condition     = !datadog_monitor.error_rate[0].notify_no_data
    error_message = "The error-ratio monitor must not page on missing data — a quiet night is not an outage."
  }

  # The traffic monitor is the compensating control, and it is the ONE that must
  # fire on silence: an API emitting no metrics at all is exactly what the
  # error-ratio monitor cannot see.
  assert {
    condition     = datadog_monitor.traffic_drop[0].notify_no_data
    error_message = "The traffic-drop monitor MUST alert on no-data — it is the only thing watching for silence."
  }
}

run "the_slo_target_matches_the_cloudwatch_burn_rate_alarms" {
  command = plan

  variables {
    datadog_api_key = "0123456789abcdef0123456789abcdef"
    datadog_app_key = "0123456789abcdef0123456789abcdef01234567"
  }

  # burn_rate.tf computes budget against a 99.5% availability SLO. If these two
  # disagree, the same incident pages on one backend and not the other — which is
  # worse than having only one.
  assert {
    condition     = datadog_service_level_objective.availability[0].thresholds[0].target == 99.5
    error_message = "The Datadog SLO target must match the 99.5% the CloudWatch burn-rate alarms are computed against."
  }
}
