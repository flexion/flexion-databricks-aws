locals {
  name_prefix = var.name_prefix

  common_tags = {
    Project     = "Flexion-Databricks"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Random suffix to keep S3 bucket names globally unique.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ---------- Networking ----------
module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

# ---------- S3 (root bucket for Databricks workspace) ----------
module "s3" {
  source = "../../modules/s3"

  name_prefix           = local.name_prefix
  bucket_suffix         = random_string.suffix.result
  databricks_account_id = var.databricks_account_id
  tags                  = local.common_tags
}

# ---------- IAM (cross-account role for Databricks control plane) ----------
module "iam" {
  source = "../../modules/iam"

  name_prefix           = local.name_prefix
  databricks_account_id = var.databricks_account_id
  tags                  = local.common_tags
}

# ---------- Databricks workspace registration ----------
module "databricks_workspace" {
  source = "../../modules/databricks-workspace"

  providers = {
    databricks = databricks.mws
  }

  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  databricks_account_id = var.databricks_account_id

  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.databricks_security_group_id

  cross_account_role_arn = module.iam.cross_account_role_arn
  root_bucket_name       = module.s3.root_bucket_name

  workspace_admins = var.admin_user_emails
}

# ---------- Workspace-level access control ----------
module "access_control" {
  source = "../../modules/access-control"

  providers = {
    databricks = databricks.workspace
  }

  name_prefix         = local.name_prefix
  admin_user_emails   = var.admin_user_emails
  sandbox_user_emails = var.sandbox_user_emails

  depends_on = [module.databricks_workspace]
}

# ---------- AWS Budgets (cost guardrail) ----------
module "budgets" {
  source = "../../modules/budgets"

  name_prefix       = local.name_prefix
  environment       = var.environment
  monthly_limit_usd = var.monthly_budget_usd
  alert_emails      = var.budget_alert_emails
}
