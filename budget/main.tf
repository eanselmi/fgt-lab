# Stack independiente del lab (./lab.sh budget deploy|destroy): se despliega una
# vez al empezar el curso y no se toca con los deploy/destroy del lab, así las
# alertas y el acumulado de créditos consumidos no se reinician.

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.project_name}-budget-alerts"
}

data "aws_iam_policy_document" "budget_sns" {
  statement {
    sid     = "AllowBudgetsPublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    resources = [aws_sns_topic.budget_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "budget_alerts" {
  arn    = aws_sns_topic.budget_alerts.arn
  policy = data.aws_iam_policy_document.budget_sns.json
}

resource "aws_sns_topic_subscription" "budget_email" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "lab" {
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
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}

# Inicio del período del budget de créditos. Lo ideal es el mes en que se abrió
# la cuenta (los créditos valen 12 meses desde ahí): lab.sh lo detecta con Cost
# Explorer (primer mes con consumo) y lo pasa en var.credits_start. Si no viene,
# se usa el día 1 del mes del primer deploy de este stack (fallback).
# Sin fecha de inicio, un budget ANNUALLY arranca el 1/1 y se resetea en enero.
resource "terraform_data" "credits_budget_start" {
  input = formatdate("YYYY-MM-01_00:00", plantimestamp())

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_budgets_budget" "credits" {
  name              = "${var.project_name}-credits-remaining"
  budget_type       = "COST"
  limit_amount      = tostring(var.credit_total)
  limit_unit        = "USD"
  time_unit         = "ANNUALLY"
  time_period_start = var.credits_start != "" ? var.credits_start : terraform_data.credits_budget_start.output

  cost_types {
    include_credit = false
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.credit_total - 10
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}
