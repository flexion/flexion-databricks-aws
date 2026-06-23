output "sandbox_policy_id" {
  value = databricks_cluster_policy.sandbox.id
}

output "sandbox_users_group_id" {
  value = databricks_group.sandbox_users.id
}
