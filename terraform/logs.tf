# Stage 1 — saved CloudWatch Logs Insights queries over the observed Lambdas' logs.
# These turn raw logs into a few one-click investigations.

locals {
  log_group_names = [for f in var.lambda_functions : "/aws/lambda/${f}"]
}

resource "aws_cloudwatch_query_definition" "errors" {
  name            = "${var.name_prefix}/lambda-errors"
  log_group_names = local.log_group_names
  query_string    = <<-QUERY
    fields @timestamp, @log, @message
    | filter @message like /(?i)(error|exception|traceback|timed out|access denied)/
    | sort @timestamp desc
    | limit 50
  QUERY
}

resource "aws_cloudwatch_query_definition" "slowest" {
  name            = "${var.name_prefix}/lambda-slowest-invocations"
  log_group_names = local.log_group_names
  query_string    = <<-QUERY
    filter @type = "REPORT"
    | fields @timestamp, @log, @duration, @billedDuration, @requestId
    | sort @duration desc
    | limit 25
  QUERY
}

resource "aws_cloudwatch_query_definition" "cold_starts" {
  name            = "${var.name_prefix}/lambda-cold-starts"
  log_group_names = local.log_group_names
  query_string    = <<-QUERY
    filter @type = "REPORT" and ispresent(@initDuration)
    | fields @timestamp, @log, @initDuration, @requestId
    | sort @initDuration desc
    | limit 25
  QUERY
}

resource "aws_cloudwatch_query_definition" "reaper_deletions" {
  name            = "${var.name_prefix}/reaper-self-destructs"
  log_group_names = ["/aws/lambda/sfs-reaper"]
  query_string    = <<-QUERY
    fields @timestamp, @message
    | filter @message like /reaped/
    | sort @timestamp desc
    | limit 50
  QUERY
}
