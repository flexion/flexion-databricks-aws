output "workspace_url" {
  description = "URL of the deployed Databricks workspace."
  value       = module.databricks_workspace.workspace_url
}

output "workspace_id" {
  description = "Databricks workspace ID."
  value       = module.databricks_workspace.workspace_id
}

output "vpc_id" {
  description = "VPC ID hosting the Databricks data plane."
  value       = module.vpc.vpc_id
}

output "root_bucket_name" {
  description = "S3 bucket used as the workspace root storage (DBFS root)."
  value       = module.s3.root_bucket_name
}

output "cross_account_role_arn" {
  description = "IAM role ARN trusted by Databricks control plane."
  value       = module.iam.cross_account_role_arn
}

output "sandbox_cluster_policy_id" {
  description = "ID of the cluster policy that sandbox users must use."
  value       = module.access_control.sandbox_policy_id
}

output "monthly_budget_name" {
  description = "Name of the AWS Budgets alarm guarding monthly spend."
  value       = module.budgets.budget_name
}
