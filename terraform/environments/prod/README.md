# Prod environment — placeholder

Prod is wired up after dev reaches steady state. The dev environment in `../dev/` is the source of truth for module composition.

**v1 simplification: dev and prod share a single `Flexion Databricks` AWS account.** They are isolated by VPC, IAM resource names (via `name_prefix`), Databricks workspace, and tag-based budget filters — but they live in the same AWS account. The "When to split" section below lists triggers for moving to separate accounts.

## When to populate this directory

When all of these are true:

- Dev has run for at least one full month under real usage with no firefighting.
- Cost actuals match the `CostAnalysis.md` model within ±25%.
- The cluster policy guardrails have proven sufficient — no incident where a sandbox user spun up unexpected compute.
- A separate Databricks workspace has been registered (don't share a workspace between dev and prod).

## How to populate it

1. Copy every `.tf` file from `../dev/` into this directory.
2. In `versions.tf`, change the backend `key` from `databricks/dev/terraform.tfstate` to `databricks/prod/terraform.tfstate`.
3. In `terraform.tfvars`, set:
   - `environment        = "prod"`
   - `name_prefix        = "flexion-databricks-prod"`
   - `vpc_cidr           = "10.41.0.0/16"` (must not collide with dev's `10.40.0.0/16`)
   - `availability_zones = ["us-east-2a", "us-east-2b"]`
   - Tighter `monthly_budget_usd` if appropriate, plus the prod budget alert distribution.
4. Use the same AWS access keys as dev (same account). Same Databricks service principal credentials work too — the workspace it registers will be a new prod workspace within the existing Databricks account.
5. `terraform init` (downloads providers + initializes the prod state file in S3).
6. `terraform plan` → review → `terraform apply`.

## Why dev and prod can share the AWS account

Each environment isolates itself via:

- **`name_prefix`** — distinct resource names (`flexion-databricks-dev-*` vs. `flexion-databricks-prod-*`). No collisions.
- **`vpc_cidr`** — distinct CIDR blocks per env. The VPCs do not peer.
- **Tags** — the `Environment` tag is set on every resource and feeds the `budgets` module's cost filter, so each env has its own $100/month alarm.
- **Databricks workspace** — separate workspaces, separate cluster policies, separate user groups.
- **State file** — namespaced as `databricks/dev/terraform.tfstate` vs `databricks/prod/terraform.tfstate` in the same bucket.

## When to split into separate AWS accounts

Convert to separate accounts when any of these become true:

- **Real client/customer data lands in prod.** Account-level isolation becomes the right blast radius.
- **AWS quotas start binding.** Two NAT gateways, four VPCs, etc., compete for per-account limits.
- **Compliance or audit requires it** — SOC 2 / HIPAA / FedRAMP scope often defines the boundary at the account.
- **Independent cost ownership emerges** — when prod is funded under a project budget separate from R&D.

The migration path is straightforward but real work: provision a `Flexion Databricks Prod` AWS account, re-deploy prod via Terraform there, transfer DBFS / Delta data manually, point users at the new workspace, decommission the prod resources in the shared account.

## What's different in prod

Track these decisions here as they get made:

- _(no entries yet — dev has not reached steady state)_
