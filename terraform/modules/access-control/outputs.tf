output "sandbox_policy_id" {
  value = databricks_cluster_policy.sandbox.id
}

output "sandbox_users_group_id" {
  value = databricks_group.sandbox_users.id
}

output "admin_user_ids" {
  description = "Map of admin user email to Databricks user ID."
  value       = { for k, v in databricks_user.admin : k => v.id }
}
