# Stage 4 — CloudWatch Synthetics canary: an outside-in uptime probe of the live app.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "canary" {
  bucket        = "${var.name_prefix}-canary-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "canary" {
  bucket                  = aws_s3_bucket.canary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/../canary"
  output_path = "${path.module}/build/canary.zip"
}

data "aws_iam_policy_document" "canary_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "canary" {
  name               = "${var.name_prefix}-canary-role"
  assume_role_policy = data.aws_iam_policy_document.canary_assume.json
}

data "aws_iam_policy_document" "canary" {
  statement {
    actions   = ["s3:PutObject", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.canary.arn, "${aws_s3_bucket.canary.arn}/*"]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/cwsyn-*"]
  }
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CloudWatchSynthetics"]
    }
  }
  statement {
    actions   = ["xray:PutTraceSegments"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "canary" {
  name   = "${var.name_prefix}-canary-inline"
  role   = aws_iam_role.canary.id
  policy = data.aws_iam_policy_document.canary.json
}

resource "aws_synthetics_canary" "uptime" {
  name                 = "sfs-uptime"
  artifact_s3_location = "s3://${aws_s3_bucket.canary.bucket}/canary"
  execution_role_arn   = aws_iam_role.canary.arn
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  handler              = "apiCanary.handler"
  zip_file             = data.archive_file.canary.output_path
  start_canary         = true

  schedule {
    # hourly keeps canary cost ~$0.86/mo (5-min would be ~$10/mo) — fine for a hobby app
    expression = "rate(1 hour)"
  }

  run_config {
    timeout_in_seconds = 60
    environment_variables = {
      TARGET_URL = var.uptime_url
    }
  }
}
