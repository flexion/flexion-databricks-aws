resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Filter on Project AND Environment so dev and prod budgets stay
  # independent when both environments share an AWS account.
  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$Flexion-Databricks",
    ]
  }

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Environment$${var.environment}",
    ]
  }

  # 50% actual
  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.alert_emails
  }

  # 80% actual
  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.alert_emails
  }

  # 100% actual
  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.alert_emails
  }

  # 100% forecasted (early warning)
  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.alert_emails
  }
}
