variable "name_prefix" {
  type = string
}

variable "bucket_suffix" {
  type = string
}

variable "databricks_account_id" {
  type      = string
  sensitive = true
}

variable "aws_account_id" {
  type = string
}

variable "catalog_name" {
  type    = string
  default = "sandbox"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "metastore_id" {
  description = "ID of the existing Unity Catalog metastore to bring under Terraform management."
  type        = string
}

variable "metastore_name" {
  description = "Display name of the metastore (must match the name shown in the Account Console)."
  type        = string
}

variable "admin_user_ids" {
  description = "Map of admin user email to Databricks user ID. Passed from the access-control module to avoid MWS data source lookups that fail before users are created."
  type        = map(string)
  default     = {}
}

variable "terraform_sp_client_id" {
  description = "Client ID of the Terraform service principal — added to metastore admins so it can manage system schema grants."
  type        = string
  sensitive   = true
}
