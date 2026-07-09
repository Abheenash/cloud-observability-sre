# Real User Monitoring for the portfolio site — real visitor sessions, page views,
# web-vitals performance, JS errors, and custom click events, straight from the browser.

# RUM sends events from the browser via an unauthenticated Cognito identity.
resource "aws_cognito_identity_pool" "rum" {
  identity_pool_name               = "${var.name_prefix}-rum"
  allow_unauthenticated_identities = true
}

data "aws_iam_policy_document" "rum_guest_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.rum.id]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["unauthenticated"]
    }
  }
}

resource "aws_iam_role" "rum_guest" {
  name               = "${var.name_prefix}-rum-guest"
  assume_role_policy = data.aws_iam_policy_document.rum_guest_assume.json
}

# The browser guest may only send RUM events to this one app monitor.
resource "aws_iam_role_policy" "rum_guest" {
  name = "rum-put-events"
  role = aws_iam_role.rum_guest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rum:PutRumEvents"
      Resource = "arn:aws:rum:${var.region}:${data.aws_caller_identity.current.account_id}:appmonitor/${var.rum_monitor_name}"
    }]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "rum" {
  identity_pool_id = aws_cognito_identity_pool.rum.id
  roles = {
    unauthenticated = aws_iam_role.rum_guest.arn
  }
}

resource "aws_rum_app_monitor" "portfolio" {
  name           = var.rum_monitor_name
  domain         = var.portfolio_domain
  cw_log_enabled = true

  app_monitor_configuration {
    identity_pool_id    = aws_cognito_identity_pool.rum.id
    guest_role_arn      = aws_iam_role.rum_guest.arn
    allow_cookies       = true
    enable_xray         = false
    session_sample_rate = 1
    telemetries         = ["errors", "performance", "http"]
  }
}
