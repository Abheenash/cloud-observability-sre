# Datadog: monitors, an SLO and a dashboard, as code.
#
# This repo now expresses the same golden signals three ways — CloudWatch
# (alarms.tf, burn_rate.tf), Splunk (splunk.tf, for log search), and Datadog
# here. That is not redundancy for its own sake: each is what a different
# employer already runs, and the differences are real. docs/three-backends.md
# has the comparison.
#
# Off by default. `datadog_api_key` empty creates nothing — there is no Datadog
# org behind this account, and monitors pointing at an org that does not exist
# would just fail to create.

locals {
  datadog_enabled = var.datadog_api_key != ""
  # Datadog's metric names for AWS integrations. The AWS integration polls
  # CloudWatch, so these are the same underlying numbers the alarms in alarms.tf
  # read — which is exactly what makes the comparison honest.
  dd_filter = "service:${var.name_prefix}"
}

# --- monitors ---------------------------------------------------------------

# Datadog monitors take a single query string rather than a metric + statistic +
# threshold. That is more expressive than a CloudWatch alarm — this one is a
# ratio across two metrics, which CloudWatch needs metric MATH to express — and
# it is also easier to get subtly wrong, because the whole thing is a string that
# is only validated server-side.
resource "datadog_monitor" "error_rate" {
  count = local.datadog_enabled ? 1 : 0

  name    = "[${var.name_prefix}] API 5xx ratio above SLO"
  type    = "query alert"
  message = <<-EOT
    The API's 5xx ratio is above the 0.5% error budget.

    Runbook: https://github.com/Abheenash/cloud-observability-sre/blob/main/docs/runbook.md

    {{#is_alert}}Paging — the error budget is burning.{{/is_alert}}
    {{#is_recovery}}Recovered.{{/is_recovery}}
    @${var.datadog_notify}
  EOT

  query = "sum(last_5m):sum:aws.apigateway.5xxerror{${local.dd_filter}}.as_count() / sum:aws.apigateway.count{${local.dd_filter}}.as_count() > 0.005"

  monitor_thresholds {
    critical = 0.005
    warning  = 0.002
  }

  # The CloudWatch equivalent of treat_missing_data. `notify_no_data = false`
  # here for the same reason the CloudWatch error alarms use notBreaching: no
  # requests means no errors, which is a quiet night, not an outage. The
  # traffic-drop monitor below is what catches actual silence.
  notify_no_data    = false
  renotify_interval = 60

  tags = ["service:${var.name_prefix}", "slo:availability", "managed-by:terraform"]
}

resource "datadog_monitor" "traffic_drop" {
  count = local.datadog_enabled ? 1 : 0

  name    = "[${var.name_prefix}] No traffic reaching the API"
  type    = "query alert"
  message = "Request volume has fallen to zero — the front door may be down. @${var.datadog_notify}"

  query = "sum(last_15m):sum:aws.apigateway.count{${local.dd_filter}}.as_count() <= 0"

  monitor_thresholds {
    critical = 0
  }

  # This is the one monitor that MUST fire on missing data: an API emitting no
  # metrics at all is the exact failure the error-ratio monitor cannot see.
  notify_no_data      = true
  no_data_timeframe   = 20
  require_full_window = false

  tags = ["service:${var.name_prefix}", "managed-by:terraform"]
}

# --- SLO --------------------------------------------------------------------

# A first-class object, which CloudWatch has no equivalent for. In alarms.tf the
# SLO exists only as arithmetic inside a burn-rate alarm; here it is a resource
# with a target, a window and a queryable error budget.
resource "datadog_service_level_objective" "availability" {
  count = local.datadog_enabled ? 1 : 0

  name        = "[${var.name_prefix}] API availability"
  type        = "metric"
  description = "99.5% of API requests succeed, measured over 30 days."

  query {
    numerator   = "sum:aws.apigateway.count{${local.dd_filter}}.as_count() - sum:aws.apigateway.5xxerror{${local.dd_filter}}.as_count()"
    denominator = "sum:aws.apigateway.count{${local.dd_filter}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.5
    warning   = 99.9
  }

  tags = ["service:${var.name_prefix}", "managed-by:terraform"]
}

# --- dashboard --------------------------------------------------------------

resource "datadog_dashboard" "golden_signals" {
  count = local.datadog_enabled ? 1 : 0

  title       = "[${var.name_prefix}] Golden signals"
  layout_type = "ordered"
  description = "Traffic, errors, latency and saturation. Mirrors the CloudWatch dashboard in dashboard.tf and the Grafana one in aws-eks-platform."

  widget {
    service_level_objective_definition {
      title        = "Availability SLO"
      slo_id       = datadog_service_level_objective.availability[0].id
      view_type    = "detail"
      time_windows = ["30d"]
      view_mode    = "overall"
    }
  }

  widget {
    timeseries_definition {
      title = "Traffic — requests"
      request {
        q            = "sum:aws.apigateway.count{${local.dd_filter}}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Errors — 5xx ratio"
      request {
        q            = "sum:aws.apigateway.5xxerror{${local.dd_filter}}.as_count() / sum:aws.apigateway.count{${local.dd_filter}}.as_count()"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      # p50/p95/p99 of ONE measure share ONE axis. A second y-axis mixing
      # latency and request count would be unreadable.
      title = "Latency — p50 / p95 / p99"
      request {
        q            = "p50:aws.apigateway.latency{${local.dd_filter}}"
        display_type = "line"
      }
      request {
        q            = "p95:aws.apigateway.latency{${local.dd_filter}}"
        display_type = "line"
      }
      request {
        q            = "p99:aws.apigateway.latency{${local.dd_filter}}"
        display_type = "line"
      }
    }
  }
}
