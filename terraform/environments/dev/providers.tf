provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Flexion-Databricks"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = var.owner
    }
  }
}

# Databricks Account-level provider (used to register the workspace via the
# account API). The "accounts" host is region-specific.
provider "databricks" {
  alias      = "mws"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  client_id  = var.databricks_client_id
  client_secret = var.databricks_client_secret
}

# Databricks Workspace-level provider (used after the workspace is created).
provider "databricks" {
  alias = "workspace"
  host  = module.databricks_workspace.workspace_url
  token = module.databricks_workspace.workspace_token
}
