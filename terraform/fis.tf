# AWS Fault Injection Service: the Stage-5 drill as a repeatable, scheduled-able
# experiment instead of a hand-typed CLI command.
#
# The experiment runs the SSM runbook in fis/throttle-lambda.yaml against
# sfs-issue-url. Its STOP CONDITION is the composite service-health alarm: the
# moment detection fires, FIS aborts the experiment and the runbook's onCancel
# restores concurrency. So one run answers two questions — "does the alarm catch
# it?" and "how long did that take?" — and cannot leave production throttled.

resource "aws_ssm_document" "throttle_lambda" {
  name            = "${var.name_prefix}-throttle-lambda"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../fis/throttle-lambda.yaml")
}

data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ssm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

# The automation may change concurrency on exactly the observed functions, nothing else.
data "aws_iam_policy_document" "automation" {
  statement {
    actions   = ["lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency", "lambda:GetFunctionConcurrency"]
    resources = [for f in var.lambda_functions : "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${f}"]
  }
}

resource "aws_iam_role" "automation" {
  name               = "${var.name_prefix}-automation-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume.json
}

resource "aws_iam_role_policy" "automation" {
  name   = "throttle-observed-lambdas"
  role   = aws_iam_role.automation.id
  policy = data.aws_iam_policy_document.automation.json
}

data "aws_iam_policy_document" "fis" {
  statement {
    actions = ["ssm:StartAutomationExecution"]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.throttle_lambda.name}:*",
    ]
  }
  statement {
    actions   = ["ssm:GetAutomationExecution", "ssm:StopAutomationExecution"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:automation-execution/*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.automation.arn]
  }
  statement {
    actions   = ["logs:CreateLogDelivery", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "fis" {
  name               = "${var.name_prefix}-fis-role"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
}

resource "aws_iam_role_policy" "fis" {
  name   = "run-throttle-automation"
  role   = aws_iam_role.fis.id
  policy = data.aws_iam_policy_document.fis.json
}

resource "aws_fis_experiment_template" "throttle_issue_url" {
  description = "GameDay: throttle sfs-issue-url to 0 and prove the service-health alarm catches it"
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "throttle-issue-url"
    action_id = "aws:ssm:start-automation-execution"
    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:document/${aws_ssm_document.throttle_lambda.name}"
    }
    parameter {
      key   = "documentParameters"
      value = jsonencode({ FunctionName = var.lambda_functions[0], DurationSeconds = "420", AutomationAssumeRole = aws_iam_role.automation.arn })
    }
    parameter {
      key   = "maxDuration"
      value = "PT10M"
    }
  }

  # Detection IS the stop condition: when the composite alarm fires, FIS cancels the
  # automation and the runbook's onCancel path restores concurrency.
  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_composite_alarm.service_health.arn
  }

  tags = { Name = "${var.name_prefix}-gameday-throttle" }
}

output "fis_experiment_template_id" {
  value = aws_fis_experiment_template.throttle_issue_url.id
}
