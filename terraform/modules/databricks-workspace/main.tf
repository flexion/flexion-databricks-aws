terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks]
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

# IAM roles and inline policies take up to ~20s to propagate globally.
# Without this delay, Databricks credential and network validation fail
# with AccessDenied even though the role and policy were just created.
resource "time_sleep" "iam_propagation" {
  create_duration = "20s"

  triggers = {
    role_arn   = var.cross_account_role_arn
    policy_id  = var.cross_account_policy_id
  }
}

# Register the cross-account credential with Databricks.
resource "databricks_mws_credentials" "this" {
  provider         = databricks
  credentials_name = "${var.name_prefix}-creds"
  role_arn         = time_sleep.iam_propagation.triggers["role_arn"]
}

# Register the network configuration (VPC + subnets + SG).
resource "databricks_mws_networks" "this" {
  provider           = databricks
  account_id         = var.databricks_account_id
  network_name       = "${var.name_prefix}-network"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]
}

# Register the workspace storage configuration (root S3 bucket).
resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks
  account_id                 = var.databricks_account_id
  storage_configuration_name = "${var.name_prefix}-storage"
  bucket_name                = var.root_bucket_name
}

# Create the workspace itself.
resource "databricks_mws_workspaces" "this" {
  provider       = databricks
  account_id     = var.databricks_account_id
  workspace_name = "${var.name_prefix}-sandbox"
  aws_region     = var.aws_region

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id

  pricing_tier = "PREMIUM"

  token {
    comment = "Terraform-managed workspace token"
  }
}
