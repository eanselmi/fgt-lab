locals {
  alerts_enabled = var.alert_email == "" ? 0 : 1
}

resource "aws_sns_topic" "budget_alerts" {
  count    = local.alerts_enabled
  provider = aws.us_east_1
  name     = "${var.project_name}-budget-alerts"
}

data "aws_iam_policy_document" "budget_sns" {
  count = local.alerts_enabled

  statement {
    sid     = "AllowBudgetsPublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    resources = [aws_sns_topic.budget_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "budget_alerts" {
  count    = local.alerts_enabled
  provider = aws.us_east_1
  arn      = aws_sns_topic.budget_alerts[0].arn
  policy   = data.aws_iam_policy_document.budget_sns[0].json
}

resource "aws_sns_topic_subscription" "budget_email" {
  count     = local.alerts_enabled
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.budget_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "lab" {
  count        = local.alerts_enabled
  name         = "${var.project_name}-budget"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts[0].arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts[0].arn]
  }
}
