terraform {
  # Floor: latest stable Terraform CLI as of 2026-06-18 (v1.15.6).
  # 1.10+ is required for native S3 state locking (use_lockfile = true).
  # Use `tfenv` and the .terraform-version file in the repo root to
  # match this automatically.
  required_version = ">= 1.15.6, < 2.0.0"

  # Provider constraints: floor at known-stable major versions.
  # The exact build is locked in .terraform.lock.hcl. To refresh to
  # the latest patch/minor, run `terraform init -upgrade` and commit
  # the updated lockfile. See deploy.md → "Refreshing versions".
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor: latest stable as of 2026-06-18 (v6.51.0).
      version = ">= 6.51, < 7.0"
    }
    databricks = {
      source = "databricks/databricks"
      # Floor: latest stable as of 2026-06-18 (v1.118.0).
      version = ">= 1.118, < 2.0"
    }
    random = {
      source = "hashicorp/random"
      # Floor: latest stable as of 2026-06-18 (v3.9.0).
      version = ">= 3.9, < 4.0"
    }
  }

  # Remote state in S3 with native locking (Terraform 1.10+ — no DynamoDB).
  # Bucket must be created out-of-band before the first `terraform init`.
  # Refer to deploy.md Section 3 for the one-time bucket bootstrap.
  backend "s3" {
    bucket       = "flexion-databricks-tfstate"
    key          = "databricks/dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
