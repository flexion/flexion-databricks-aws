output "catalog_name" {
  value = databricks_catalog.this.name
}

output "storage_credential_name" {
  value = databricks_storage_credential.unity_catalog.name
}

output "external_location_name" {
  value = databricks_external_location.unity_catalog.name
}

output "unity_catalog_bucket" {
  value = aws_s3_bucket.unity_catalog.bucket
}

output "unity_catalog_role_arn" {
  value = aws_iam_role.unity_catalog.arn
}
