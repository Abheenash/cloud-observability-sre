# Forward the observed service's logs to Splunk HEC.
#
# The SLOs, alarms and dashboards here are CloudWatch-native. Most enterprises
# centralise on Splunk, so this is the seam between the two: a subscription
# filter on each observed log group delivers batches to a Lambda that speaks HEC.
#
# The whole thing is behind `var.splunk_hec_url != ""`, so the default deployment
# creates nothing. There is no Splunk instance in this account and a forwarder
# pointing nowhere would just fill a DLQ.

locals {
  splunk_enabled = var.splunk_hec_url != ""
}

data "archive_file" "splunk_forwarder" {
  count       = local.splunk_enabled ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../src/splunk_forwarder"
  output_path = "${path.module}/build/splunk_forwarder.zip"
}

data "aws_iam_policy_document" "splunk_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "splunk_forwarder" {
  count              = local.splunk_enabled ? 1 : 0
  name               = "${var.name_prefix}-splunk-forwarder"
  assume_role_policy = data.aws_iam_policy_document.splunk_assume.json
}

# The HEC token is a bearer credential: anything holding it can write to the
# index. It lives in SSM as a SecureString and is read at runtime — never an
# environment variable, which would expose it in the console and in every
# GetFunctionConfiguration call.
data "aws_iam_policy_document" "splunk_forwarder" {
  count = local.splunk_enabled ? 1 : 0

  statement {
    sid       = "ReadTheHecTokenOnly"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.splunk_hec_token[0].arn]
  }

  statement {
    sid       = "DecryptThatParameter"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-splunk-forwarder:*"]
  }
}

resource "aws_iam_role_policy" "splunk_forwarder" {
  count  = local.splunk_enabled ? 1 : 0
  name   = "${var.name_prefix}-splunk-forwarder"
  role   = aws_iam_role.splunk_forwarder[0].id
  policy = data.aws_iam_policy_document.splunk_forwarder[0].json
}

# A customer-managed key rather than the AWS-managed SSM key: the HEC token is a
# bearer credential for the log index, and a CMK lets its access be revoked
# independently of the parameter's own IAM.
# An explicit key policy. KMS's default grants the account root full control and
# nothing else — workable, but it leaves the key's permissions entirely in IAM
# with no statement on the key itself. Spelling it out makes "who can decrypt the
# HEC token?" a question this file answers.
data "aws_iam_policy_document" "splunk_key" {
  count = local.splunk_enabled ? 1 : 0

  statement {
    sid       = "EnableIAMUserPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowSSMToUseTheKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.splunk_forwarder[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "splunk" {
  count                   = local.splunk_enabled ? 1 : 0
  description             = "Encrypts the Splunk HEC token"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.splunk_key[0].json
}

resource "aws_kms_alias" "splunk" {
  count         = local.splunk_enabled ? 1 : 0
  name          = "alias/${var.name_prefix}-splunk-hec"
  target_key_id = aws_kms_key.splunk[0].key_id
}

resource "aws_ssm_parameter" "splunk_hec_token" {
  count  = local.splunk_enabled ? 1 : 0
  name   = "/${var.name_prefix}/splunk/hec-token"
  type   = "SecureString"
  key_id = aws_kms_key.splunk[0].key_id
  value  = var.splunk_hec_token

  lifecycle {
    # The real token is set out of band; Terraform should not own its value or
    # it ends up in state and in every plan output.
    ignore_changes = [value]
  }
}

resource "aws_cloudwatch_log_group" "splunk_forwarder" {
  count             = local.splunk_enabled ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-splunk-forwarder"
  retention_in_days = 14
}

resource "aws_lambda_function" "splunk_forwarder" {
  count            = local.splunk_enabled ? 1 : 0
  function_name    = "${var.name_prefix}-splunk-forwarder"
  role             = aws_iam_role.splunk_forwarder[0].arn
  handler          = "lambda_function.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.splunk_forwarder[0].output_path
  source_code_hash = data.archive_file.splunk_forwarder[0].output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      SPLUNK_HEC_URL         = var.splunk_hec_url
      SPLUNK_HEC_TOKEN_PARAM = aws_ssm_parameter.splunk_hec_token[0].name
      SPLUNK_INDEX           = var.splunk_index
      SPLUNK_SOURCETYPE      = "aws:cloudwatchlogs"
    }
  }

  # A batch Splunk rejects must not vanish. Subscription filters invoke
  # asynchronously, so failures land here after the retries.
  dead_letter_config {
    target_arn = aws_sns_topic.alerts.arn
  }

  depends_on = [aws_cloudwatch_log_group.splunk_forwarder]
}

resource "aws_lambda_permission" "logs_invoke_splunk" {
  for_each      = local.splunk_enabled ? toset(var.lambda_functions) : toset([])
  statement_id  = "AllowCWLogs-${each.value}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.splunk_forwarder[0].function_name
  principal     = "logs.amazonaws.com"
  # A wildcard account id is not a valid ARN here — the provider rejects it. Using
  # the real account also narrows the permission to this account's log groups,
  # which is what it should have said in the first place.
  source_arn = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${each.value}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "to_splunk" {
  for_each = local.splunk_enabled ? toset(var.lambda_functions) : toset([])

  name            = "${var.name_prefix}-to-splunk"
  log_group_name  = "/aws/lambda/${each.value}"
  destination_arn = aws_lambda_function.splunk_forwarder[0].arn

  # Forward only the app's own structured JSON lines. An empty pattern would also
  # ship START/END/REPORT for every invocation — roughly tripling the volume, and
  # Splunk licensing is priced per GB ingested per day.
  filter_pattern = "{ $.rid = * }"

  depends_on = [aws_lambda_permission.logs_invoke_splunk]
}
