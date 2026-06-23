variable "name_prefix" {
  type = string
}

variable "environment" {
  description = "Environment tag value (e.g., dev, prod). Used to scope the budget when dev and prod share an AWS account."
  type        = string
}

variable "monthly_limit_usd" {
  description = "Monthly USD budget cap (alerts only — does not stop spend)."
  type        = number
  default     = 100
}

variable "alert_emails" {
  description = "Email addresses to notify on budget thresholds."
  type        = list(string)
}
