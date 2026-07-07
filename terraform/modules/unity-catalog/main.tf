terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.mws, databricks.workspace]
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

# ---------- S3 bucket for Unity Catalog metastore storage ----------
resource "aws_s3_bucket" "unity_catalog" {
  bucket = "${var.name_prefix}-unity-catalog-${var.bucket_suffix}"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-unity-catalog-${var.bucket_suffix}" })
}

resource "aws_s3_bucket_versioning" "unity_catalog" {
  bucket = aws_s3_bucket.unity_catalog.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unity_catalog" {
  bucket = aws_s3_bucket.unity_catalog.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "unity_catalog" {
  bucket                  = aws_s3_bucket.unity_catalog.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- IAM role for Unity Catalog storage credential ----------
# Unity Catalog uses a separate role from the cross-account role.
# Trust policy references the Databricks Unity Catalog service principal.
data "aws_iam_policy_document" "unity_catalog_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::414351767826:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }

  # Allow self-assumption required by Unity Catalog credential validation.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-unity-catalog-role"]
    }
  }
}

data "aws_iam_policy_document" "unity_catalog_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.unity_catalog.arn,
      "${aws_s3_bucket.unity_catalog.arn}/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-unity-catalog-role"]
  }
}

resource "aws_iam_role" "unity_catalog" {
  name               = "${var.name_prefix}-unity-catalog-role"
  assume_role_policy = data.aws_iam_policy_document.unity_catalog_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "unity_catalog" {
  name   = "${var.name_prefix}-unity-catalog-policy"
  role   = aws_iam_role.unity_catalog.id
  policy = data.aws_iam_policy_document.unity_catalog_s3.json
}

# ---------- Databricks storage credential ----------
resource "databricks_storage_credential" "unity_catalog" {
  provider = databricks.workspace
  name     = "${var.name_prefix}-storage-credential"

  aws_iam_role {
    role_arn = aws_iam_role.unity_catalog.arn
  }
}

# IAM role for the storage credential takes time to propagate before
# Databricks can validate READ access on the external location.
resource "time_sleep" "unity_catalog_iam_propagation" {
  create_duration = "20s"

  triggers = {
    role_arn    = aws_iam_role.unity_catalog.arn
    policy_id   = aws_iam_role_policy.unity_catalog.id
  }
}

# ---------- Databricks external location ----------
resource "databricks_external_location" "unity_catalog" {
  provider        = databricks.workspace
  name            = "${var.name_prefix}-external-location"
  url             = "s3://${aws_s3_bucket.unity_catalog.bucket}"
  credential_name = databricks_storage_credential.unity_catalog.name

  depends_on = [time_sleep.unity_catalog_iam_propagation]
}

# Grant all workspace users read access to the external location so it
# appears in the UI and can be selected when creating catalogs.
resource "databricks_grants" "external_location" {
  provider          = databricks.workspace
  external_location = databricks_external_location.unity_catalog.name

  grant {
    principal  = "account users"
    privileges = ["READ FILES", "WRITE FILES", "CREATE EXTERNAL TABLE", "CREATE MANAGED STORAGE"]
  }
}

# ---------- Catalog ----------
resource "databricks_catalog" "this" {
  provider     = databricks.workspace
  name         = var.catalog_name
  storage_root = "s3://${aws_s3_bucket.unity_catalog.bucket}/catalog"

  properties = {
    purpose = "sandbox"
  }

  depends_on = [databricks_external_location.unity_catalog]
}

# Grant catalog-level privileges to admins and sandbox users.
resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  catalog  = databricks_catalog.this.name

  grant {
    principal  = "account users"
    privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"]
  }
}
