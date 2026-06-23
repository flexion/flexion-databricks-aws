output "workspace_id" {
  value = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  value = "https://${databricks_mws_workspaces.this.workspace_url}"
}

output "workspace_token" {
  value     = databricks_mws_workspaces.this.token[0].token_value
  sensitive = true
}
