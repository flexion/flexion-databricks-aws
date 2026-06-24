# Flexion Databricks on AWS

Infrastructure-as-Code to deploy a Databricks workspace in a dedicated Flexion AWS account. The workspace is intended to serve as an internal **sandbox** where Flexioneers can explore Databricks capabilities — notebooks, workflows, Delta Lake, Spark, and ML — to build hands-on experience that translates to client engagements.

This is an **initial version (v1)** — simple, admin-gated, and cost-capped. Items deferred to later iterations are tracked in the Next Steps section, with rationale captured under What's in Scope and Assumptions.

---

## Why this exists

Flexioneers want hands-on experience with Databricks to support delivery work on data-platform engagements. This repo provisions a shared internal Databricks environment for that purpose. Following the pattern of other Flexion-hosted tools (Moodle LMS, Odoo CRM, LLM Development), Databricks gets its own AWS account so usage, costs, and access can be cleanly isolated.

---

## What's in scope (v1)

- **One environment, `dev`.** Repo structured for two (`environments/dev/` + `environments/prod/`); prod is a placeholder, populated once dev reaches steady state.
- Dedicated **VPC** with public/private subnets across 2 AZs, single NAT Gateway, security group with the egress rules Databricks requires.
- **S3 root bucket** for the workspace (versioned, encrypted, public access blocked, with the standard Databricks bucket policy).
- **IAM cross-account role** trusted by the Databricks-owned AWS account (with the standard Databricks policy and `external_id` scoping).
- **Databricks workspace** registered via the Databricks account API.
- **Restrictive sandbox cluster policy** that non-admin users must use:
  - Default `m6i.large` for driver and workers; `m6i.xlarge` allowed as an upgrade. No other instance types permitted. Refer to `CostAnalysis.md` Section 7 for justification and Section 8 for the vertical-scaling path.
  - Max 2 workers, max 60 min auto-termination.
  - Spot instances for workers (with on-demand fallback).
  - Max 1 cluster per user.
- **Two-tier access model:**
  - **Admins** — full workspace control. Configurable via `admin_user_emails` (list of Flexion emails); start with ~3 so the workspace stays manageable when one admin is unavailable.
  - **Sandbox users** — `CAN_USE` permission on the sandbox cluster policy and nothing else.
- **AWS Budgets alarm** at $100/month (~25% headroom over the $80.79 AWS Pricing Calculator estimate) with notifications at 50%, 80%, 100% actual, and 100% forecasted spend.
- **Remote Terraform state** in S3 with native S3 locking (no DynamoDB). State is namespaced per environment in a single bucket: `databricks/dev/terraform.tfstate`, `databricks/prod/terraform.tfstate`.
- Standard tags on every AWS resource (`Project=Flexion-Databricks`).

## What's out of scope (v1)

Items deferred to a later iteration. Triggers for revisiting each one are noted alongside the rationale.

- **Google SSO integration.** Workspace uses native Databricks accounts (email invite + password). Flexion uses Google Workspace as its IdP and SSO can be enabled later via the workspace admin console without re-deploying Terraform.
- **Unity Catalog.** The legacy Hive metastore that ships with the workspace is sufficient for exploration. UC adds governance + cross-workspace data sharing — worth doing once there are real datasets to govern.
- **VPC endpoints** for S3/STS/Kinesis. Reduce NAT data costs but each endpoint costs ~$7/month — not worth it at sandbox scale.
- **Custom KMS keys** for encryption. Default S3 AES256 is sufficient.
- **CloudTrail** / audit log delivery. Useful at scale, overkill for ~5 users.
- **VPC peering / Transit Gateway** to other Flexion accounts.
- **Multi-NAT-Gateway** high availability. Single NAT is fine for a sandbox.
- **GitHub Actions CI/CD.** v1 deployment is local apply only. Trajectory through to plan-on-PR + manual prod gate is in `deploy.md` → "CI/CD trajectory".
- **Prod environment.** `terraform/environments/prod/` is a placeholder; populated once dev is stable. Driven by criteria in that directory's README.

---

## Assumptions

- **Small admin group.** A handful of named admins (start with ~3) hold full workspace control and budget visibility. Other Flexioneers join as `sandbox-users` and are bound to the sandbox cluster policy.
- **Light usage.** ~5 Flexioneers, ~30 cluster-hours/week aggregate. Sized for ~$80/month AWS spend, ~$80/month Databricks DBUs. Refer to `CostAnalysis.md`.
- **`us-east-2` region.** Aligns with the rest of the Flexion AWS estate.
- **Premium Databricks pricing tier.** Required for cluster policies and audit logs. Standard would lose those.
- **Terraform authenticates via a Databricks service principal** with the account-admin role from v1 onward. Credentials are captured in `DatabricksSetup.md` Stage 5b.
- **AWS account is dedicated to Databricks.** Following the Flexion pattern (Moodle LMS, Odoo CRM, etc.). Does not share an account with other workloads.
- **Dev and prod share the same AWS account.** Isolated by VPC, name prefix, Databricks workspace, and tag-based budget filters. Convert to separate AWS accounts later if real client data lands in prod, AWS quotas bind, or compliance requires it. Refer to `terraform/environments/prod/README.md` → "When to split".

---

## What this repo contains

```
flexion-databricks-aws/
├── README.md                  # Repo overview, scope, assumptions
├── DatabricksSetup.md         # Databricks signup — must be completed before deploy.md
├── deploy.md                  # Step-by-step Terraform deployment instructions
├── CostAnalysis.md            # Pre-fill values for AWS Pricing Calculator
├── CLAUDE.md                  # Context for Claude sessions
├── .terraform-version         # Pinned Terraform CLI version (tfenv)
└── terraform/
    ├── modules/                       # Shared across environments
    │   ├── vpc/                       # Dedicated VPC, subnets, NAT, SG
    │   ├── s3/                        # Workspace root bucket
    │   ├── iam/                       # Cross-account role for Databricks
    │   ├── databricks-workspace/      # Registers workspace via account API
    │   ├── access-control/            # Cluster policy + admin/user groups
    │   └── budgets/                   # AWS Budgets monthly alarm
    └── environments/
        ├── dev/                       # Active — provisioned today
        │   ├── versions.tf
        │   ├── providers.tf
        │   ├── variables.tf
        │   ├── main.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars.example
        └── prod/                      # Placeholder — populated when dev is stable
            └── README.md
```

## High-level architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Databricks Control Plane (Databricks-managed AWS account)      │
│  - Workspace UI / REST API                                      │
│  - Notebooks, jobs, metastore                                   │
└────────────────┬────────────────────────────────────────────────┘
                 │ HTTPS, assume-role
┌────────────────▼────────────────────────────────────────────────┐
│  Flexion Databricks AWS Account (data plane)                    │
│                                                                 │
│  ┌──────────── VPC (10.40.0.0/16) ───────────────────────────┐  │
│  │  Public subnet ── NAT GW ── IGW                          │  │
│  │  Private subnet (AZ-a) ──┐                               │  │
│  │  Private subnet (AZ-b) ──┴── EC2 cluster nodes            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  S3 (workspace root: notebooks, logs, DBFS)                    │
│  IAM cross-account role  AWS Budgets ($100/mo)                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- A dedicated **`Flexion Databricks` AWS account** (matching the pattern of `Flexion LLM Development`, `Flexion Moodle LMS`, etc.). Provisioned only after Flexion approves the new-account request based on the cost estimate in [`CostAnalysis.md`](CostAnalysis.md).
- A **Databricks account** registered with the Flexion-owned email associated with the AWS account. Refer to `DatabricksSetup.md` Stage 4.
- A **Databricks service principal** with account-admin role for Terraform auth. Refer to `DatabricksSetup.md` Stage 5b.
- Local tooling: `terraform 1.15.6` (use `tfenv install` to pick up the pinned version), `awscli >= 2.x`, `databricks` CLI (optional).

**Order of operations:**
1. Use [`CostAnalysis.md`](CostAnalysis.md) to produce a cost estimate for the new AWS account request.
2. Once the dedicated `Flexion Databricks` AWS account is provisioned, follow [`DatabricksSetup.md`](DatabricksSetup.md) Stages 1-5 for Databricks signup and credential capture.
3. Run [`deploy.md`](deploy.md) for the Terraform deployment.
4. Complete [`DatabricksSetup.md`](DatabricksSetup.md) Stage 6 (AWS Marketplace billing linkage) before the 14-day Databricks trial expires.

---

## Cost expectations

This is a sandbox — costs depend almost entirely on how many people are running clusters at any given time. With `m6i.large` defaults, cluster auto-termination, and spot worker nodes, expected spend is roughly **$80–$150/month AWS** at light to moderate use. Databricks DBUs add another **~$80–$220/month** on top. AWS Budgets is configured to alert at $100/month — ~25% above the calculator's $80 light-scenario estimate, so the 100% threshold fires when something has actually changed rather than as routine noise.

Refer to `CostAnalysis.md` for line-item assumptions to paste into the AWS Pricing Calculator.

---

## Guardrails baked in

- **Cluster policy** restricts users to small instance types and short auto-termination — preventing accidentally-expensive compute.
- **Spot instances** for worker nodes (60–70% savings vs on-demand).
- **Single NAT Gateway** instead of one per AZ (sandbox tradeoff).
- **S3 versioning + encryption + public access block** on the root bucket.
- **AWS Budgets** notifies the admin at 50% / 80% / 100% / forecasted-100%.
- **Cross-account IAM role** scoped via Databricks `external_id`.

---

## Next steps

Items planned for later iterations, ordered by priority:

1. **GitHub Actions CI/CD for dev** — plan-on-PR + apply-on-merge, AWS auth via OIDC. Refer to `deploy.md` → "CI/CD trajectory".
2. **Populate the prod environment** — copy `terraform/environments/dev/` into `terraform/environments/prod/`, separate Databricks workspace, distinct VPC CIDR. Same AWS account at v1 — refer to `terraform/environments/prod/README.md`.
3. **GitHub Actions CI/CD for prod** — manual `workflow_dispatch` with required-reviewer gate.
4. **Enable Google Workspace SSO** at the workspace level — single sign-on for Flexioneers, no separate password to manage.
5. **Codify the workspace getting-started notebook** as a `databricks_notebook` resource so first-time users land on something useful.
6. **Add Unity Catalog** (metastore + storage credential + catalog) once there are shared datasets that need governance.
7. **Add CloudTrail + Databricks audit log delivery** when usage grows past ~10 users.
8. **Tighten the IAM cross-account policy** to remove any actions Databricks doesn't actually need (the v1 policy is the broad default).
9. **Add VPC endpoints** if NAT data-processing costs become a meaningful fraction of monthly spend.
10. **Multi-AZ NAT Gateway** if the sandbox graduates to anything resembling a production workload.
11. **Right-size the budget** — start at $100, adjust once usage patterns are known.

---