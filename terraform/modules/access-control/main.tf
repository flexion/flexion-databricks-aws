terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks]
    }
  }
}

# ---------- Restrictive cluster policy for sandbox users ----------
# Forces small, auto-terminating, spot-backed clusters so non-admins
# can experiment without spinning up expensive infrastructure.
resource "databricks_cluster_policy" "sandbox" {
  provider = databricks
  name     = "${var.name_prefix}-sandbox-policy"

  definition = jsonencode({
    "spark_version" = {
      "type"         = "allowlist"
      "values"       = ["15.4.x-scala2.12", "14.3.x-scala2.12"]
      "defaultValue" = "15.4.x-scala2.12"
    },
    "node_type_id" = {
      "type"         = "allowlist"
      "values"       = ["m6i.large", "m6i.xlarge"]
      "defaultValue" = "m6i.large"
    },
    "driver_node_type_id" = {
      "type"         = "allowlist"
      "values"       = ["m6i.large", "m6i.xlarge"]
      "defaultValue" = "m6i.large"
    },
    "autotermination_minutes" = {
      "type"         = "range"
      "minValue"     = 10
      "maxValue"     = 60
      "defaultValue" = 30
    },
    "num_workers" = {
      "type"         = "range"
      "minValue"     = 0
      "maxValue"     = 2
      "defaultValue" = 1
    },
    "aws_attributes.availability" = {
      "type"         = "fixed"
      "value"        = "SPOT_WITH_FALLBACK"
      "hidden"       = false
    },
    "aws_attributes.first_on_demand" = {
      "type"  = "fixed"
      "value" = 1
    },
    "aws_attributes.spot_bid_price_percent" = {
      "type"         = "range"
      "minValue"     = 50
      "maxValue"     = 100
      "defaultValue" = 100
    },
    "cluster_log_conf.type" = {
      "type"  = "fixed"
      "value" = "S3"
    }
  })

  max_clusters_per_user = 1
}

# ---------- Workspace users group ----------
# Members can use the sandbox policy to create clusters but nothing else.
resource "databricks_group" "sandbox_users" {
  provider     = databricks
  display_name = "${var.name_prefix}-sandbox-users"
}

# Grant the users group permission to USE (not edit) the sandbox cluster policy.
resource "databricks_permissions" "sandbox_policy_use" {
  provider          = databricks
  cluster_policy_id = databricks_cluster_policy.sandbox.id

  access_control {
    group_name       = databricks_group.sandbox_users.display_name
    permission_level = "CAN_USE"
  }
}

# ---------- Admins ----------
# Add named admin users from var.admin_user_emails to the workspace
# admin group. The "admins" group is created by Databricks automatically.
resource "databricks_user" "admin" {
  provider  = databricks
  for_each  = toset(var.admin_user_emails)
  user_name = each.value
}

data "databricks_group" "admins" {
  provider     = databricks
  display_name = "admins"
}

resource "databricks_group_member" "admin" {
  provider  = databricks
  for_each  = databricks_user.admin
  group_id  = data.databricks_group.admins.id
  member_id = each.value.id
}

# ---------- Sandbox users (regular workspace members) ----------
resource "databricks_user" "sandbox_user" {
  provider  = databricks
  for_each  = toset(var.sandbox_user_emails)
  user_name = each.value
}

resource "databricks_group_member" "sandbox_user" {
  provider  = databricks
  for_each  = databricks_user.sandbox_user
  group_id  = databricks_group.sandbox_users.id
  member_id = each.value.id
}
