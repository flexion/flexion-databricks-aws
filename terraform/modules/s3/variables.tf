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

variable "tags" {
  type    = map(string)
  default = {}
}
