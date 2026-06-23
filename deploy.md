# Deployment Guide — Flexion Databricks on AWS

This document walks through deploying the Databricks sandbox end-to-end.

> **Before starting:** This guide assumes the Databricks account already exists and its account ID and auth credentials are in hand. If not, work through [`DatabricksSetup.md`](DatabricksSetup.md) first — it covers signup and credential capture.

---

## 1. Prerequisites

[`DatabricksSetup.md`](DatabricksSetup.md) Stages 1-5 must be complete. By the time the user reaches this guide, the following are in hand:

- A dedicated **Flexion Databricks AWS account** in the AWS access portal (Stage 3).
- A **Databricks account** with its `databricks_account_id` captured (Stage 5a).
- A **Databricks service principal** with `client_id` and `client_secret` (Stage 5b).
- AWS access portal admin role for the new account.

Local tools required:

- `terraform 1.15.6` (pinned in `.terraform-version`). With `tfenv` installed, run `tfenv install` from the repo root to pick it up. Otherwise install directly from https://releases.hashicorp.com/terraform/.
- `awscli >= 2.x`
- `git`

---

## 2. Configure local credentials

### 2a. AWS access keys (short-lived, from the access portal)

1. Sign in to https://d-9a6729e262.awsapps.com/start (federated through Google SSO).
2. Find the `Flexion Databricks` account and click **Access keys** next to the `AdministratorAccess` role.
3. Paste the credentials block from the portal into `~/.aws/credentials`:

   ```ini
   [flexion-databricks]
   aws_access_key_id     = <from portal>
   aws_secret_access_key = <from portal>
   aws_session_token     = <from portal>
   region                = us-east-2
   ```

4. Activate the profile and confirm:

   ```bash
   export AWS_PROFILE=flexion-databricks
   aws sts get-caller-identity   # sanity check
   ```

> Credentials expire after a few hours. Re-fetch from the portal when they do.

### 2b. Databricks account credentials

The three values from `DatabricksSetup.md` Stage 5 (`databricks_account_id`, `databricks_client_id`, `databricks_client_secret`) feed into Terraform via either `terraform/environments/dev/terraform.tfvars` or `TF_VAR_*` environment variables.

---

## 3. Bootstrap the Terraform state bucket (one-time)

The dev environment's backend is already configured for S3 with native locking (`terraform/environments/dev/versions.tf`). The state bucket must exist before the first `terraform init` — create it once with the steps below.

State keys are namespaced per environment in the same bucket: `databricks/dev/terraform.tfstate`, `databricks/prod/terraform.tfstate`. **Terraform 1.10+ uses native S3 state locking** via a `.tflock` file in the same bucket; no DynamoDB table required.

```bash
aws s3api create-bucket \
  --bucket flexion-databricks-tfstate \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

# Bucket layout once both environments are live:
#   s3://flexion-databricks-tfstate/databricks/dev/terraform.tfstate
#   s3://flexion-databricks-tfstate/databricks/prod/terraform.tfstate

aws s3api put-bucket-versioning \
  --bucket flexion-databricks-tfstate \
  --versioning-configuration Status=Enabled

# Block public access (defense in depth — state files contain secrets).
aws s3api put-public-access-block \
  --bucket flexion-databricks-tfstate \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable default encryption.
aws s3api put-bucket-encryption \
  --bucket flexion-databricks-tfstate \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

The first `terraform init` (Section 5) reads the backend block and writes state to `s3://flexion-databricks-tfstate/databricks/dev/terraform.tfstate`.

---

## 4. Configure the deployment

The repo has two environments under `terraform/environments/` — `dev/` and `prod/` (placeholder, populated later when dev reaches steady state). All Terraform commands run from inside an environment directory.

```bash
git clone <this-repo>
cd flexion-databricks-aws/terraform/environments/dev

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and fill in:
#   - databricks_account_id
#   - databricks_client_id
#   - databricks_client_secret
#   - admin_user_emails
```

---

## 5. Apply Terraform

From `terraform/environments/dev/`:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

> **First-time setup:** on the very first `terraform init` in a freshly cloned repo, also run `terraform init -upgrade` once to resolve providers to the latest versions allowed by the constraints in `versions.tf`, then commit the updated `.terraform.lock.hcl`. Refer to "Refreshing versions" below for the ongoing workflow.

> Workspace registration through the Databricks account API is the slow step in `apply` — leave it running rather than killing it.

Outputs include:

```
workspace_url           = "https://dbc-xxxxxxxx-xxxx.cloud.databricks.com"
workspace_id            = "1234567890123456"
vpc_id                  = "vpc-0abc123def456"
root_bucket_name        = "flexion-databricks-dev-root-ab12cd"
cross_account_role_arn  = "arn:aws:iam::<account-id>:role/flexion-databricks-dev-cross-account-role"
```

---

## 6. First-time workspace setup

The cluster policy, admin/sandbox-user groups, and AWS Budgets alarm are all created by Terraform on `apply`. What remains is verification and onboarding additional users.

1. Open `workspace_url` from the Terraform output. Each email in `admin_user_emails` receives a workspace invite (separate from the account-level signup in `DatabricksSetup.md` Stage 4) — accept and set a password.
2. **Verify the cluster policy.** Compute → Cluster policies. Expect `flexion-databricks-dev-sandbox-policy` with `m6i.large`, max 2 workers, 60 min auto-term.
3. **Verify the budgets alarm.** AWS Console → Billing → Budgets. Expect `flexion-databricks-dev-monthly` at $100/month.
4. **Add other Flexioneers** by appending their emails to `sandbox_user_emails` in `terraform.tfvars` and re-running `terraform apply`:
   ```hcl
   sandbox_user_emails = [
     "alice@flexion.us",
     "bob@flexion.us",
   ]
   ```
   They land in the `flexion-databricks-dev-sandbox-users` group with `CAN_USE` on the cluster policy and nothing else — clusters can be created within the policy's limits; unrestricted compute and account-level settings are blocked.

> **Workspace-level Google SSO** (so Flexioneers sign in with their `@flexion.us` accounts instead of Databricks passwords) is enabled post-deploy via **Workspace admin console → Settings → Identity and access → Single sign-on**. Deferred to v2; see README's "Next steps".

---

## 7. Smoke test

From the workspace UI:

1. Create a new cluster using the sandbox cluster policy.
2. Open a new notebook and run:
   ```python
   spark.range(10).show()
   ```
3. Confirm logs land in the S3 root bucket: check `s3://flexion-databricks-dev-root-<suffix>/cluster-logs/`.

---

## Refreshing versions

**Why pin.** `terraform/environments/dev/versions.tf` declares loose constraints (e.g., `aws >= 6.51, < 7.0`). The exact provider builds are pinned in `.terraform.lock.hcl`, which **is** committed to the repo. That lockfile guarantees that any teammate (or CI, or a future deployment) gets the same provider builds on every `terraform init`.

**Refresh cadence.** Every quarter, or before a meaningful change, refresh to the latest stable releases that still satisfy the constraints:

```bash
cd terraform/environments/dev/
terraform init -upgrade
terraform plan      # sanity-check no drift
git add .terraform.lock.hcl
git commit -m "Refresh provider lockfile"
```

**Crossing a major boundary** (e.g., AWS provider 6 → 7) — bump the upper bound in `versions.tf` first, run `terraform init -upgrade`, then read the provider's upgrade guide for breaking changes before committing.

**Terraform CLI itself.** Bump `required_version` in `versions.tf` when new CLI features are required. The current floor is 1.15.6. A pre-1.10 CLI would fail with a clear error from `init` (1.10 is the absolute minimum for native S3 state locking).

---

## CI/CD trajectory (v2 — planned, not yet implemented)

v1 deployment runs locally with state in the S3 backend (Section 3). v2 work moves apply into GitHub Actions:

### Phase 1 — GitHub Actions for dev

Workflows (not yet written):
- `.github/workflows/dev-plan.yml` — runs on PRs touching `terraform/**`. Steps: `fmt-check`, `validate`, `plan`. Plan output posted as a PR comment.
- `.github/workflows/dev-apply.yml` — runs on merges to `main`. Steps: `init`, `apply -auto-approve` against dev.

Auth: GitHub OIDC federation to AWS — GitHub Actions assumes an IAM role in the dev account (no static AWS keys in GitHub Secrets). The Databricks service principal `client_id` / `client_secret` live in GitHub Secrets.

### Phase 2 — Prod environment populated

- `terraform/environments/prod/` filled in following its README.
- Separate Databricks workspace registered under the same AWS account as dev (v1 keeps both envs in one AWS account).
- Distinct VPC CIDR (`10.41.0.0/16`) and `name_prefix` (`flexion-databricks-prod`) to avoid collisions with dev resources.
- Prod state at `databricks/prod/terraform.tfstate` in the same state bucket.

### Phase 3 — GitHub Actions for prod

- `.github/workflows/prod-apply.yml` — `workflow_dispatch` only (manual trigger). Required reviewer gate. Same OIDC pattern, separate IAM role scoped to prod resources within the shared AWS account.
- Promotion convention: dev gets every merge to `main`; prod gets explicit human-triggered runs after the change has soaked in dev.

---

## Tearing it down

If the sandbox is ever decommissioned:

```bash
# Empty + delete the workspace root bucket (Terraform won't delete a non-empty bucket).
aws s3 rm s3://flexion-databricks-dev-root-<suffix> --recursive

terraform destroy
```

This removes the workspace, network, IAM role, and S3 bucket. The AWS account itself remains and can be repurposed.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `databricks_mws_credentials` fails with `INVALID_PARAMETER_VALUE` | IAM role trust policy missing the Databricks principal or wrong external ID | Re-check `databricks_account_id` matches the value in tfvars |
| `databricks_mws_workspaces` hangs > 20 min | Network/SG misconfigured (Databricks cannot reach data plane) | Verify NAT Gateway is healthy and SG allows 443 egress |
| Cluster start fails with `INSTANCE_PROFILE_NOT_FOUND` | Trying to use an instance profile that was not created here | Remove the profile reference or extend the IAM module to provision one |
| S3 bucket create fails: `BucketAlreadyExists` | Bucket name clashes globally | Re-run — `random_string.suffix` picks a new value |

---

## References

- Databricks AWS deployment docs: https://docs.databricks.com/en/admin/workspace/index.html
- Databricks Terraform provider: https://registry.terraform.io/providers/databricks/databricks/latest/docs
