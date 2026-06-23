# CLAUDE.md

Context file for Claude sessions working in this repo. Keep this file current as decisions and state change.

---

## Project

Infrastructure-as-Code to deploy a Databricks workspace in a dedicated `Flexion Databricks` AWS account. The workspace is an internal sandbox where Flexioneers explore Databricks capabilities (notebooks, Spark, Delta Lake, ML) to build skills applicable to client engagements.

This is **v1**: simple, admin-gated, cost-capped at $100/month AWS spend.

---

## Repository layout

```
flexion-databricks-aws/
├── CLAUDE.md                  # This file
├── README.md                  # Repo overview, scope, assumptions, next steps
├── DatabricksSetup.md         # Stages 1-5: cost estimate → AWS account → Databricks signup → credentials
├── deploy.md                  # Terraform deployment walkthrough; CI/CD trajectory
├── CostAnalysis.md            # AWS Pricing Calculator inputs, DBU math, instance justification, scaling path
├── .terraform-version         # 1.15.6 — picked up by tfenv
├── .gitignore                 # NOTE: .terraform.lock.hcl is NOT ignored — committed for reproducibility
└── terraform/
    ├── modules/                            # Shared by all environments
    │   ├── vpc/                            # VPC + subnets + NAT + SG
    │   ├── s3/                             # Workspace root bucket
    │   ├── iam/                            # Cross-account role for Databricks
    │   ├── databricks-workspace/           # mws_credentials, mws_networks, mws_storage, mws_workspace
    │   ├── access-control/                 # Cluster policy + admin/user groups
    │   └── budgets/                        # AWS Budgets monthly alarm
    └── environments/
        ├── dev/                            # Active — provisioned today
        │   ├── versions.tf
        │   ├── providers.tf
        │   ├── variables.tf
        │   ├── main.tf                     # Imports modules from ../../modules/
        │   ├── outputs.tf
        │   └── terraform.tfvars.example
        └── prod/                           # Placeholder — populated when dev is stable
            └── README.md                   # Criteria + steps for activation
```

**All Terraform commands run from inside an environment directory.** E.g., `cd terraform/environments/dev && terraform plan`.

---

## Read order for first-time onboarding

1. `README.md` — what this is and what's in/out of scope.
2. `CostAnalysis.md` — cost model, fed into the AWS Pricing Calculator.
3. `DatabricksSetup.md` — pre-deploy stages (AWS account approval through Databricks credential capture).
4. `deploy.md` — actual Terraform deployment.

---

## Conventions

### Documentation tone

- **Neutral, declarative voice.** No first/second-person pronouns ("you", "your", "we", "our", "I"). The exception is when quoting a UI label verbatim (e.g., the Databricks signup button "or set up with your cloud").
- **No vague verbiage.** Avoid "whatever process", "whoever", "or similar", "might", "maybe". State the concrete artifact, owner, or value.
- **Reference concrete artifacts.** "the `budgets` Terraform module" beats "what Terraform configures". Cross-link doc stages (e.g., "see DatabricksSetup.md Stage 2") instead of describing them inline twice.

### Terraform conventions

- **Module per concern.** VPC, S3, IAM, workspace, access-control, budgets each live in their own `modules/<name>/` directory with their own `main.tf` / `variables.tf` / `outputs.tf`. Modules are shared across environments — only environment-specific config lives in `environments/<env>/`.
- **Per-environment root.** Each environment in `environments/<env>/` has its own `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars`. State is namespaced by env: `databricks/dev/terraform.tfstate`, `databricks/prod/terraform.tfstate`, same bucket.
- **Shared AWS account, isolated environments.** Dev and prod live in the same AWS account at v1. Isolation is enforced by `name_prefix` (distinct resource names), `vpc_cidr` (distinct CIDRs — dev `10.40.0.0/16`, prod `10.41.0.0/16`), distinct Databricks workspaces, and tag-based budget filters (each env has its own AWS Budgets alarm filtered on `Project=Flexion-Databricks` AND `Environment=<env>`).
- **Two Databricks providers.** `databricks.mws` for account-level resources (host = `accounts.cloud.databricks.com`); `databricks.workspace` for workspace-level resources (host = workspace URL, token from workspace creation). The `access-control` module uses the workspace alias; everything else uses `mws`.
- **Tags.** AWS provider's `default_tags` sets `Project = "Flexion-Databricks"`, `ManagedBy = "Terraform"`, `Environment`, `Owner` on every AWS resource. The `budgets` module filters on `Project=Flexion-Databricks`.
- **Standard names.** All resources prefixed with `var.name_prefix` (e.g., `flexion-databricks-dev` for the dev env, `flexion-databricks-prod` for prod).

### Version pinning

- **Floors at today's latest stable**, upper bound at the next major:
  - Terraform CLI: `>= 1.15.6, < 2.0.0`
  - AWS provider: `>= 6.51, < 7.0`
  - Databricks provider: `>= 1.118, < 2.0`
  - Random provider: `>= 3.9, < 4.0`
- **Lockfile committed.** `.terraform.lock.hcl` is the source of truth for exact builds. Commit it after every `terraform init -upgrade`.
- **Refresh quarterly.** Run `terraform init -upgrade` → `terraform plan` → commit lockfile. Refer to `deploy.md` → "Refreshing versions".
- **`tfenv` integration.** `.terraform-version` at repo root pins to `1.15.6`. `tfenv install` from the repo root picks it up automatically.

### State

- **Remote state in S3 from v1.** Backend block is uncommented in `terraform/environments/dev/versions.tf`. Native locking via `use_lockfile = true` (no DynamoDB, since CLI is `>= 1.10`). State bucket `flexion-databricks-tfstate` must be created out-of-band before the first `terraform init` — bootstrap snippet in `deploy.md` Section 3.
- **State keys namespaced per environment** in a single bucket: `databricks/dev/terraform.tfstate`, `databricks/prod/terraform.tfstate`.

---

## Current state (as of 2026-06-19)

### Done

- Terraform IaC complete and structured into modules; dev environment fully wired, prod is a placeholder with activation criteria in its own README.
- AWS access portal URL: `https://d-9a6729e262.awsapps.com/start` (federated via Google SSO). CLI access uses **short-lived role-assumption credentials** copy-pasted from the portal into `~/.aws/credentials` (with `aws_session_token`). Not `aws configure sso`, not long-lived IAM access keys.
- Remote state in S3 with native locking is **v1**, not v2. Bucket `flexion-databricks-tfstate` bootstrap is in `deploy.md` Section 3.
- CI/CD trajectory documented (not implemented). 3 phases: GitHub Actions for dev (OIDC, plan-on-PR + apply-on-merge) → prod populated → GitHub Actions for prod (workflow_dispatch with reviewer gate). Refer to `deploy.md` → "CI/CD trajectory".

### Decisions locked in

- **No personal-account dress rehearsal.** Databricks accounts don't migrate between owners and workspaces don't transfer between accounts. The full signup happens once, with the Flexion alias email, after Brice provisions the AWS account. Don't re-suggest the personal-account path.
- **Databricks signup uses email + password, not Google SSO.** The signup email is whatever Brice associates with the new Flexion AWS account in Stage 2 (could be a Google Workspace mailbox, a forwarding alias, or a shared inbox — confirm during Stage 3 hand-off, don't presume). Workspace-level Google SSO for individual Flexioneers is a v2 item, configured post-signup in the workspace admin console.
- **Service principal only for Terraform Databricks auth.** No personal OAuth fallback. Captured in `DatabricksSetup.md` Stage 5b.
- **Single AWS account for both dev and prod (v1).** Splitting later is documented but deferred. Triggers for splitting: real client data in prod, AWS quotas binding, compliance/audit scope at the account boundary, or independent cost ownership. Refer to `terraform/environments/prod/README.md` → "When to split".

### In flight

- AWS account approval for `Flexion Databricks` — Stage 2 of `DatabricksSetup.md`.
- Databricks account signup — blocked on Stage 3 (need AWS account ID).

### Not yet done (deferred to v2)

Refer to `README.md` → "Next steps" for the prioritized list. Top items:

1. GitHub Actions CI/CD for dev (OIDC, plan-on-PR + apply-on-merge).
2. Populate the prod environment.
3. GitHub Actions CI/CD for prod (workflow_dispatch + reviewer gate).
4. Enable Google Workspace SSO at the workspace level.
5. Add Unity Catalog (metastore + storage credential + catalog).

---

## Working with this repo

### First-time setup on a new machine

```bash
cd flexion-databricks-aws
tfenv install                           # picks up .terraform-version → 1.15.6
cd terraform/environments/dev/
cp terraform.tfvars.example terraform.tfvars
# fill in tfvars (see DatabricksSetup.md Stage 5)
terraform init -upgrade                 # resolves providers to latest in constraints
git add .terraform.lock.hcl             # commit the resulting lockfile
terraform validate                      # sanity check, no auth needed
```

### Common tasks

- **Add a sandbox user.** Edit `sandbox_user_emails` in `terraform/environments/dev/terraform.tfvars`, run `terraform apply`. Invitee lands in the `flexion-databricks-dev-sandbox-users` group.
- **Adjust the cost cap.** Edit `monthly_budget_usd` in `terraform/environments/dev/terraform.tfvars`. Default $100 — chosen to give ~25% headroom over the AWS Pricing Calculator estimate of $80.79/month so the alarm stays meaningful.
- **Refresh provider versions.** Refer to `deploy.md` → "Refreshing versions" for the full flow. Commit the updated `.terraform.lock.hcl`.

### Non-obvious things

- The `workspace_url` output is `https://...` — the `databricks_mws_workspaces.workspace_url` attribute itself is hostname-only (the module prepends the scheme).
- The `s3` module's bucket policy grants `arn:aws:iam::414351767826:root` (the Databricks-owned AWS account) and conditions on `aws:PrincipalTag/DatabricksAccountId`. Don't change those without checking the Databricks docs first.
- The `iam` module's cross-account policy is the broad default published by Databricks. Tightening it is a "Next steps" item, not v1 work.
- `databricks_mws_workspaces` registration is the slowest step in `apply` (workspace provisioning happens server-side via the Databricks account API). Apply timeouts at default values are fine; don't kill the run prematurely.

---

## Gotchas

- **Region mismatch.** Databricks workspace region and `aws_region` in tfvars must match. Both should be `us-east-2`.
- **Pricing tier.** Workspace must be Premium, not Standard. The cluster policy resource fails on Standard.
- **CloudFormation auto-setup at signup.** Databricks pushes a CloudFormation quick-start on the signup page. Decline it — it pre-creates AWS resources that Terraform also creates, causing conflicts.
- **PAT vs account auth.** A Databricks workspace personal access token (PAT) cannot create workspaces — that requires account-level auth (the service principal from `DatabricksSetup.md` Stage 5b). The `databricks_mws_*` resources are account-scoped.
- **Bucket name uniqueness.** S3 bucket name is global; `random_string.suffix` makes it unique. If `BucketAlreadyExists` fires, rerun.
- **`databricks_mws_workspaces` hangs > 20 min** usually means NAT/SG misconfigured — Databricks can't reach the data plane. Verify NAT health and SG egress 443.

---

## Maintaining this file

When something changes — a new module, a deferred item gets done, a gotcha is discovered, a convention shifts — update the relevant section of this file. Treat it as the canonical orientation doc for any new Claude session opening this repo.

**What belongs here:** project state, architectural decisions, conventions, gotchas, current focus, open items.

**What doesn't:** transcripts of past conversations, narrative recaps, unverified speculation.
