variable "aws_region" {
  description = "AWS region where Databricks workspace will be deployed."
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment tag (sandbox, dev, prod)."
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Owner tag — typically the team or admin responsible."
  type        = string
  default     = "flexion-platform"
}

variable "name_prefix" {
  description = "Prefix used to name all resources."
  type        = string
  default     = "flexion-databricks"
}

# ---------- Databricks account credentials ----------
variable "databricks_account_id" {
  description = "Databricks account ID (from accounts.cloud.databricks.com)."
  type        = string
  sensitive   = true
}

variable "databricks_client_id" {
  description = "Databricks service principal client ID for account API."
  type        = string
  sensitive   = true
}

variable "databricks_client_secret" {
  description = "Databricks service principal client secret for account API."
  type        = string
  sensitive   = true
}

# ---------- Networking ----------
variable "vpc_cidr" {
  description = "CIDR block for the Databricks VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread Databricks subnets across (need at least 2)."
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

# ---------- Access control ----------
variable "admin_user_emails" {
  description = "Email addresses to add to the workspace admins group (full control)."
  type        = list(string)
  default     = []
}

variable "sandbox_user_emails" {
  description = "Email addresses to add as restricted sandbox users (CAN_USE on the sandbox cluster policy only)."
  type        = list(string)
  default     = []
}

# ---------- Budgets ----------
variable "monthly_budget_usd" {
  description = "Monthly USD budget cap for AWS Budgets alerts."
  type        = number
  default     = 100
}

variable "budget_alert_emails" {
  description = "Email addresses notified when budget thresholds are crossed."
  type        = list(string)
}
