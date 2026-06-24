# Setting Up Databricks for Flexion

This doc covers everything that has to happen **before and after** the Terraform deployment. Six stages, ordered — each one unlocks the next:

```
1. Cost estimate     →  2. AWS account approval     →  3. Provision AWS account
                                                          ↓
                                4. Sign up Databricks  ←  ┘
                                          ↓
                                5. Capture credentials   →  deploy.md  →  6. AWS Marketplace billing linkage
```

The deliverables Terraform needs (`databricks_account_id`, `databricks_client_id`, `databricks_client_secret`) become available after Stage 5. **Stage 6 is a billing-only step** — it does not affect the Terraform deployment and can be completed any time after Stage 2 as long as it is done before the 14-day trial expires.

---

## Stage 1 — Produce the cost estimate

The dedicated AWS account needs cost justification. Use [`CostAnalysis.md`](CostAnalysis.md) to fill out the AWS Pricing Calculator at https://calculator.aws.

Hand-off after this stage:
- Public link to the AWS Pricing Calculator estimate.
- Summary of expected monthly cost (light + moderate scenarios from `CostAnalysis.md`).
- Note on Databricks DBU charges (separate from AWS, ~$80-220/month at the modeled scenarios — see `CostAnalysis.md` Section 3).

---

## Stage 2 — Get AWS account approval

Share the cost estimate from Stage 1 with Brice so he can spin up a new AWS account for Databricks (similar to `Flexion Moodle LMS`, `Flexion Odoo CRM`, `Flexion LLM Development`).

Expect follow-up questions before the account is provisioned.

---

## Stage 3 — Provision the AWS account

Once approved, the new account is created and added to the Flexion AWS access portal at https://d-9a6729e262.awsapps.com/start/. Sign-in is federated through Google SSO — the portal URL redirects to Google for authentication with a `@flexion.us` account, then back.

After the new account is live:

1. Sign in to the Flexion AWS access portal at https://d-9a6729e262.awsapps.com/start (federated through Google SSO).
2. Find the `Flexion Databricks` account in the portal and click **Access keys** next to the `AdministratorAccess` role. The portal displays short-lived role-assumption credentials in a copy-paste format.
3. Paste the credentials block into `~/.aws/credentials`, replacing or adding a `[flexion-databricks]` profile:

   ```ini
   [flexion-databricks]
   aws_access_key_id     = <from portal>
   aws_secret_access_key = <from portal>
   aws_session_token     = <from portal>
   region                = us-east-2
   ```

4. Confirm the profile works:

   ```bash
   export AWS_PROFILE=flexion-databricks
   aws sts get-caller-identity   # confirm the account ID matches
   ```

Capture the **12-digit AWS Account ID** — it is provided to Databricks during signup.

> The credentials in `~/.aws/credentials` expire after a few hours. When they expire, re-fetch them from the portal and paste the new block.

---

## Stage 4 — Sign up for Databricks

Databricks signup uses **email + password**. The email is the one Brice associates with the new Flexion AWS account in Stage 2 (capture it during Stage 3 hand-off if it's not already known). Whether it's a personal Google Workspace mailbox, a forwarding alias, or a shared inbox, signup verification works the same way — Databricks sends a confirmation link to that address.

1. Go to https://www.databricks.com/try-databricks.
2. Click **"For work"** and provide the Flexion-owned email associated with the AWS account.
3. Set a password (store it in the Flexion shared password manager, not personally).
4. Databricks sends a verification email. Click the link to complete signup.
5. After verification, Databricks presents the choice between **"Start trial with express setup"** and **"Set up with your cloud"**. Choose **"Set up with your cloud"**. Express setup runs the workspace on Databricks-managed AWS, which is incompatible with this repo.
6. **Cloud:** AWS.
7. **Region:** `us-east-2`, matching the AWS account.
8. **AWS Account ID:** the 12-digit ID from Stage 3.
9. **Workspace setup method:** Choose **Manual configuration**. Decline any CloudFormation auto-setup — it pre-creates AWS resources that conflict with this Terraform.
10. When prompted for cross-account role / S3 bucket details: **skip or use placeholder values**. The Terraform in this repo creates them and registers them via the account API.
11. **Pricing tier:** **Premium**. Required for cluster policies, which the access-control module relies on. Standard would cause the deployment to fail mid-apply.

The signup grants a $400 / 14-day trial credit, sufficient for the initial deployment and smoke test.

> Google SSO at the workspace level (so individual Flexioneers sign in with their `@flexion.us` accounts) is configured **after** signup, in the workspace admin console. It is deferred to v2 — see README's "Next steps".

> **Optional acceleration:** Stage 6 (AWS Marketplace billing linkage) can be completed immediately after Stage 4 instead of waiting until after Terraform deploy. Doing it early locks in the AWS-Marketplace billing path during the trial period and avoids any risk of the trial expiring before linkage is set up. The trade-off is committing the Flexion Databricks AWS account to this Databricks account for billing — which is the intended end state anyway.

---

## Stage 5 — Capture Databricks credentials

After signup the next page is https://accounts.cloud.databricks.com.

### 5a. Account ID

- Click the **profile icon** (top-right) → the dropdown shows the **Account ID** (a GUID like `12345678-1234-1234-1234-123456789012`).
- Also visible in the URL: `?account_id=...`.

This is the value for `databricks_account_id`.

### 5b. Service principal for Terraform

Use a service principal — not personal OAuth — so credentials don't expire on logout and audit logs show automation as the actor.

1. **User management → Service principals → Add service principal.**
   - Name: `terraform-flexion-databricks`.
2. Open the new service principal → **Roles** → toggle **Account admin** ON.
3. **OAuth secrets** tab → **Generate secret**.
   - Lifetime: 365 days. Set a calendar reminder to rotate.
   - **Copy both `Client ID` and `Secret` immediately.** The secret is shown only once.

Store the values in `terraform/environments/dev/terraform.tfvars` (gitignored):

```hcl
databricks_account_id    = "12345678-..."
databricks_client_id     = "<service-principal-client-id>"
databricks_client_secret = "dose_..."
```

Or, preferred, as environment variables (no on-disk footprint):

```bash
export TF_VAR_databricks_account_id="12345678-..."
export TF_VAR_databricks_client_id="<...>"
export TF_VAR_databricks_client_secret="dose_..."
```

---

## Final `terraform/environments/dev/terraform.tfvars`

```hcl
aws_region         = "us-east-2"
environment        = "dev"
name_prefix        = "flexion-databricks-dev"
availability_zones = ["us-east-2a", "us-east-2b"]

databricks_account_id    = "<from Stage 5a>"
databricks_client_id     = "<from Stage 5b>"
databricks_client_secret = "<from Stage 5b>"

admin_user_emails   = ["admin1@flexion.us", "admin2@flexion.us", "admin3@flexion.us"]
sandbox_user_emails = []

monthly_budget_usd  = 100
budget_alert_emails = ["admin1@flexion.us"]
```

---

## Common gotchas

- **CloudFormation quick-start ≠ this repo.** Databricks signup pushes a CloudFormation auto-setup option. Decline it — it pre-creates AWS resources that this Terraform also creates, which causes conflicts.
- **The account email is the de-facto owner.** The email on the Databricks account is the only one that can perform certain account-level operations (deletion, billing changes). A shared Flexion alias avoids ownership-transfer headaches if the admin changes.
- **Trial credits don't extend.** $400 / 14 days is real. Switch billing on before the trial expires if the deployment is going to outlive it.
- **Region mismatch.** The Databricks workspace region and `aws_region` in `terraform.tfvars` must match. Both should be `us-east-2`.
- **Pricing tier.** Pick **Premium** during signup. Standard breaks the cluster policy resource later.

---

## Next: deploy.md

With Stages 1-5 complete, Terraform has everything it needs. Continue with [`deploy.md`](deploy.md). After deployment is validated, return for Stage 6.

---

## Stage 6 — AWS Marketplace billing linkage

This stage links the Databricks account to AWS Marketplace billing so usage gets charged through the Flexion AWS account instead of being invoiced directly by Databricks. It does **not** affect the Terraform deployment — it is a one-time billing setup that must be completed before the 14-day Databricks trial expires.

Each AWS Marketplace account can be linked to only one Databricks account, so this AWS account is then committed to this Databricks account for billing purposes.

### Cost implications

The linkage itself does not change DBU rates. What it can change is set by the specific **AWS Growth Offer** terms Databricks extends to Flexion at signup.

### Steps

1. Sign in to the Databricks account console as an account admin: https://accounts.cloud.databricks.com.
2. Left navigation → **Settings** → **Subscription & billing** → **Add payment method**.
3. Select **AWS Marketplace account** as the payment method. This opens AWS Marketplace in a new tab.
4. Complete the AWS Marketplace flow in AWS by subscribing/confirming the offer.
5. **Click "Set up your account"** on the AWS confirmation page after subscribing. This step is required to complete the linkage; skipping it is the most common failure mode.
6. Back in Databricks, confirm the AWS Marketplace payment method appears under **Subscription & billing**. Use the menu next to it to set it as the primary payment method if needed.

### If something fails

Common message: "already accepted" or similar — usually means that AWS Marketplace account is already linked to a different Databricks account.

To debug, capture and send to the Databricks rep:

- Screenshot of the page where the flow stuck
- The AWS account ID being used for billing
- Confirmation of whether **"Set up your account"** was clicked after subscribing in AWS Marketplace
