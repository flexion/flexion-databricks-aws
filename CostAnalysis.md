# Cost Analysis — Flexion Databricks Sandbox on AWS

This document drives two things:
1. The line items pasted into the AWS Pricing Calculator at https://calculator.aws to produce the monthly estimate attached to the new-account request in [`DatabricksSetup.md`](DatabricksSetup.md) Stage 1.
2. The Databricks-side DBU math that the AWS calculator does not cover.

**Saved estimate (as of 2026-06-23):** [AWS Pricing Calculator — AWS Sandbox Databricks](https://calculator.aws/#/estimate?id=3261a552449b3c289c7ca8d8084681b27e1ea6a0) — **$80.79/month AWS** for the light-usage scenario.

> **Assumed scenario:** A small Flexion sandbox in `us-east-2`, used by ~5 Flexioneers on average, ~6 hours/week of cluster runtime each (≈30 cluster-hours/week, ≈130 cluster-hours/month). Auto-termination and spot instances enabled. Workspace on Databricks Premium tier.

---

## 1. Always-on AWS costs (independent of cluster usage)

These run 24×7 regardless of whether anyone is using Databricks.

### NAT Gateway
| Field | Value |
|---|---|
| Service | NAT Gateway |
| Region | US East (Ohio) |
| Number of NAT Gateways | 1 |
| Hours per month | 730 |
| Data processed (GB/month) | 50 |

**Monthly cost:** **$35.10** (per AWS Pricing Calculator)
- $0.045/hour × 730 = $32.85
- $0.045/GB × 50 = $2.25

### Elastic IP
| Field | Value |
|---|---|
| Service | EC2 / Elastic IP |
| Number of EIPs | 1 (attached to NAT) |

**Monthly cost:** $0 (free while attached to a running NAT).

### S3 — workspace root bucket
| Field | Value |
|---|---|
| Service | S3 Standard |
| Region | US East (Ohio) |
| Storage (GB/month) | 50 |
| PUT/COPY/POST/LIST requests | 50,000 |
| GET/SELECT requests | 200,000 |
| Data returned (GB/month) | 10 |
| Data scanned (S3 Select) | 0 |

**Monthly cost:** **$1.49** (per AWS Pricing Calculator)

### CloudWatch Logs (Databricks cluster logs)
| Field | Value |
|---|---|
| Service | CloudWatch Logs |
| Data ingested (GB/month) | 5 |
| Storage (GB/month) | 5 |
| Retention | 30 days |

**Monthly cost:** **$3.77** (per AWS Pricing Calculator)

### VPC + IGW + Route Tables + SGs
**Monthly cost:** $0 (no charge for these resources themselves).

**Always-on subtotal:** **$40.36/month**

---

## 2. Variable AWS costs (driven by cluster usage)

### Instance choice: `m6i.large`

The cluster policy defaults to **`m6i.large`** for both driver and worker nodes, with `m6i.xlarge` allowed as an upgrade. Justification for this choice is in Section 7 below.

### EC2 — cluster nodes (worker + driver)

Sandbox sizing assumption: **1 driver + 2 workers per cluster, m6i.large**, ~30 hours/week runtime in aggregate.

| Field | Value |
|---|---|
| Service | EC2 |
| Region | US East (Ohio) |
| Tenancy | Shared |
| OS | Linux |
| Workload | Steady-state — partial utilization |
| Driver: instance type | m6i.large |
| Driver: pricing model | On-Demand |
| Driver: hours/month | 130 |
| Worker: instance type | m6i.large |
| Worker: number | 2 |
| Worker: pricing model | Spot |
| Worker: hours/month | 260 (2 × 130) |
| EBS for driver | 100 GB gp3 |
| EBS for each worker | 100 GB gp3 |

**Monthly cost:** **$40.43** (per AWS Pricing Calculator)
- Driver m6i.large + EBS: **$15.72**
- Workers m6i.large + EBS (×2): **$24.71**

> The calculator priced workers closer to on-demand than to deep-discount spot. Real cost will be lower if AWS Spot pricing in `us-east-2` is favorable when clusters run; treat the $40 figure as a conservative upper bound for variable EC2.

### Data Transfer
| Field | Value |
|---|---|
| Service | EC2 Data Transfer |
| Outbound to internet (GB/month) | 20 |

**Monthly cost:** included in the EC2 line.

**Variable subtotal (light use):** **$40.43/month**

---

## 3. Databricks platform costs (NOT in AWS calculator)

Databricks charges **DBUs (Databricks Units)** on top of AWS infrastructure. The DBU bill comes from Databricks directly, not AWS, so it does **not** appear in the AWS Pricing Calculator.

### DBU pricing (verify at https://www.databricks.com/product/aws-pricing)

| Tier | All-Purpose Compute (notebooks) | Jobs Compute |
|---|---|---|
| Standard | $0.40 / DBU | $0.15 / DBU |
| Premium  | $0.55 / DBU | $0.30 / DBU |

The workspace runs on **Premium** (required for cluster policies).

The rates above are list price. An AWS Marketplace Growth Offer (set up in `DatabricksSetup.md` Stage 6) may apply a discount and shift these numbers.

### DBU consumption rate

`m6i.large` = **0.380 DBU/hour** (per Databricks instance-type pricing table). Sandbox workloads are All-Purpose Compute (interactive notebooks), so the rate applied is $0.55/DBU.

### Estimate

```
130 cluster-hours × 3 nodes × 0.380 DBU/hr × $0.55/DBU ≈ $81/month
```

---

## 4. Total monthly estimate

| Category | Light (5 users, ~30 hrs/week) | Moderate (10 users, ~80 hrs/week) |
|---|---|---|
| Always-on AWS | $40 | $40 |
| Variable AWS (EC2 + transfer) | $40 | $110 |
| Databricks DBUs | $81 | $220 |
| **Total** | **≈ $160/month** | **≈ $370/month** |

Light-scenario AWS-only cost ($80.79) comes from the [saved AWS Pricing Calculator estimate](https://calculator.aws/#/estimate?id=3261a552449b3c289c7ca8d8084681b27e1ea6a0). Databricks DBUs are billed separately by Databricks and monitored via the workspace admin console → Usage → DBU report.

The `budgets` Terraform module sets a **$100/month AWS Budgets cap** with notifications at 50% / 80% / 100% actual and 100% forecasted. The cap sits ~25% above the calculator's $80 estimate so the 100% threshold signals a real anomaly rather than routine month-end progression. Adjust `monthly_budget_usd` in `terraform.tfvars` once actual usage patterns are established.

---

## 5. AWS Pricing Calculator — fill order

When filling out the calculator, add services in this order so dependencies make sense:

1. **VPC → NAT Gateway** (1 unit, 730 hr/mo, 50 GB processed) — region US East (Ohio).
2. **Amazon S3** (Standard, 50 GB, request counts above) — region US East (Ohio).
3. **Amazon EC2 — driver** (m6i.large, On-Demand, 130 hr/mo, 100 GB gp3).
4. **Amazon EC2 — workers** (m6i.large, Spot, 260 hr/mo total, 100 GB gp3 each).
5. **Amazon CloudWatch** (5 GB ingestion, 30-day retention).
6. **Data Transfer** (20 GB outbound).

Save the estimate and capture the public link. This estimate is the artifact attached to the new-account request in [`DatabricksSetup.md`](DatabricksSetup.md) Stage 1.

---

## 6. Levers if monthly spend gets too high

| Lever | Savings |
|---|---|
| Switch all workers to Spot (already assumed) | 60–70% off worker EC2 |
| Use single-node clusters for exploration | ~66% off (no workers) |
| Drop to Databricks Standard tier | ~30% off DBUs (loses cluster policies and other Premium-only features) |
| Auto-terminate at 30 min instead of 60 min | 10–25% off cluster hours |
| Schedule sandbox down nights/weekends | Up to 70% off cluster hours |
| Reduce policy max workers from 2 to 1 | ~33% off cluster compute |

---

## 7. Instance-class justification — why `m6i.large`

The cluster policy allows two instance sizes (`m6i.large` default, `m6i.xlarge` upgrade). The reasoning behind picking the `m6i` family over alternatives:

| Family | DBU/hr (.large) | EC2 $/hr (.large) | Status | Notes |
|---|---|---|---|---|
| `m4` | 0.400 | $0.060 | Deprecated (Nitro-incompatible) | Avoid for new workloads |
| `m5` | 0.340 | $0.096 | Stable, older | Skylake (2017) |
| `m5a` | 0.310 | $0.086 | Stable | AMD; older silicon, no clear advantage |
| `m5d` / `m5dn` / `m5n` | 0.34–0.41 | $0.096+ | Stable | NVMe / network variants — wasted at sandbox scale |
| **`m6i`** | **0.380** | **$0.096** | **Current Intel (Ice Lake, 2021)** | **Selected default** |
| `m6g` / `m7g` / `m8g` | 0.39–0.57 | $0.090+ | Graviton ARM | ARM compatibility risks for Databricks ML stack |
| `m7i` | 0.420 | ~$0.100 | Newer (Sapphire Rapids, 2023) | 9% more expensive, no sandbox-relevant benefit |
| `m8i` | 0.470 | ~$0.106 | Newest Intel (Granite Rapids, 2024) | 20% more expensive, production-tier choice |

### Why `m6i.large` wins for v1

1. **Current-generation but cost-stable.** Ice Lake Intel; not deprecated; supported for the foreseeable future.
2. **Cheapest of the modern Intel lineup.** `m7i` and `m8i` cost more without buying anything sandbox workloads notice.
3. **Right-sized at 2 vCPU / 8 GB.** Sufficient for tutorials, exploration, small Delta tables, single-user notebooks. Driver and workers can both run on this size.
4. **No ARM compatibility risk.** Graviton variants (`m6g`, `m7g`, `m8g`) are cheaper on EC2 but periodically have ARM-vs-x86 issues with Databricks ML libraries. Not worth the support overhead for a sandbox.
5. **No wasted local NVMe.** `m6id`/`m5d` variants pay extra for local SSD that sandbox workloads do not exercise.

### What `m6i.large` is **not** suitable for

The default falls over when:

- **Memory-bound work** — joining or aggregating tables larger than ~5 GB in memory. Driver runs out of heap and Spark spills aggressively to disk.
- **High-concurrency notebooks** — more than 2-3 simultaneous notebook users on a shared cluster.
- **ML training on non-trivial datasets** — feature engineering or model training with >1 GB feature tables.
- **Any structured streaming workload** — sustained throughput needs more cores and memory than 2/8.

Hitting any of those means it is time to scale.

---

## 8. Vertical scaling path — when and how to upsize

The cluster policy is restrictive at v1 (`m6i.large` and `m6i.xlarge` only) so that exploratory users cannot accidentally provision expensive compute. When real workloads outgrow the sandbox, follow this path:

### Stage 1 — Stay within `m6i.xlarge` (already allowed)

`m6i.xlarge` (4 vCPU / 16 GB) is in the policy allowlist. Switch to it via the cluster UI — no code change needed. ~2× the cost (DBU 0.760, EC2 ~$0.192/hr).

**Indicators to upgrade:**
- Driver OOM errors on dataset joins.
- Notebook lag on basic operations (>10s for trivial Spark queries).
- Multiple users sharing a cluster and stepping on each other.

### Stage 2 — Add memory: `r6i.large` / `r6i.xlarge`

Memory-optimized R-family. Same Intel Ice Lake silicon, more RAM per vCPU (8:1 instead of 4:1). Best for SQL-heavy or feature-engineering workloads.

| Instance | vCPU | RAM | DBU/hr | EC2 $/hr |
|---|---|---|---|---|
| r6i.large | 2 | 16 | ~0.500 | ~$0.126 |
| r6i.xlarge | 4 | 32 | ~1.000 | ~$0.252 |

**Action:** add `r6i.large` and `r6i.xlarge` to the cluster policy allowlist in `terraform/modules/access-control/main.tf` and `terraform apply`.

**Indicators:** persistent driver/worker OOM at the `m6i` tier even with smaller datasets.

### Stage 3 — Add cores: `c6i.xlarge` / `c6i.2xlarge`

Compute-optimized C-family. Highest CPU-per-dollar for transformation-heavy ETL or ML feature engineering.

**Action:** extend the policy allowlist. Consider creating a *second* cluster policy ("compute-heavy") with these instances rather than expanding the sandbox policy — keeps the default-user blast radius small.

### Stage 4 — GPU for ML training: `g5.xlarge` / `g6.xlarge`

For deep learning experimentation. GPU instances are expensive (10-20× the sandbox baseline DBU + EC2) and should never be in the default policy.

**Action:** create a dedicated `ml-training-policy` cluster policy gated to a specific user group. Add a tighter auto-termination (e.g., 15 min). Add a separate AWS Budgets alarm for ML-training tagged spend.

### Stage 5 — Production workloads: separate workspace

If a Flexion delivery project needs Databricks for real client work, the answer is **not** to upsize the sandbox. Stand up a separate workspace (this Terraform with a different `name_prefix` and AWS account) governed under that project's billing and access controls.

---

## 9. Cost monitoring setup

After deploy:
- AWS Budgets alert at $100/month with notifications at 50%, 80%, 100% actual, and 100% forecasted spend (provisioned by the `budgets` Terraform module).
- Tag-based cost reports filtered on `Project=Flexion-Databricks` (default tag on every AWS resource).
- Databricks usage dashboard: workspace admin console → Usage → DBU report.
- Quarterly review by the admin to compare actual vs. budget. If consistently above budget, revisit Section 6 levers before raising the cap.
