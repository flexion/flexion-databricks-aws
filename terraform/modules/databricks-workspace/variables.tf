variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "databricks_account_id" {
  type      = string
  sensitive = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "cross_account_role_arn" {
  type = string
}

variable "root_bucket_name" {
  type = string
}

variable "workspace_admins" {
  type    = list(string)
  default = []
}
