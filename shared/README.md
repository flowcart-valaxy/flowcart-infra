# Day 2: Phase B — Shared Services Layer

Builds the resources that ALL environments (Dev/Staging/Prod) consume. Lives in the **Shared Services account** (596451157598).

## What this creates

| Resource | Quantity | Purpose |
|---|---|---|
| ECR repositories | 5 | One per microservice. Immutable tags, KMS encryption, lifecycle policy. |
| KMS keys | 2 | `flowcart-ecr` (image encryption), `flowcart-secrets` (cross-account secrets) |
| Route53 hub VPC | 1 | Tiny VPC (256 IPs) to anchor the private hosted zone |
| Route53 private zone | 1 | `flowcart.local` — accessible from any VPC we associate later |
| Route53 manager role | 1 | Cross-account role for AWS LBC / ExternalDNS to manage DNS records |
| GitHub OIDC provider | 1 | Federated identity for GitHub Actions (no long-lived AWS keys in GH) |
| GitHub Actions entry role | 1 | Role assumed by CI workflows; can chain-assume into env deployer roles |

**Cost**: ~$2/month (2 KMS keys at ~$1/key). Everything else is free or pennies.

## Prerequisites

- [x] Phase A bootstrap applied and state migrated to S3
- [x] You can run `terraform plan` in `bootstrap/` and see "No changes"
- [x] All 5 AWS CLI profiles (`flowcart`, `flowcart-shared`, `flowcart-dev`, `flowcart-staging`, `flowcart-prod`) work

Verify:

```bash
aws sts get-caller-identity --profile flowcart-shared
# Should show account 596451157598

cd ../bootstrap
terraform plan
# Should show "No changes. Your infrastructure matches the configuration."
```

## Run order

### Step 1: Initialize

```bash
cd shared/
terraform init
```

You should see:
- `Initializing the backend...` → reads remote_state from bootstrap successfully
- `Initializing provider plugins...` → downloads AWS provider 6.x
- `Terraform has been successfully initialized!`

If you get a backend error, double-check that `versions.tf` has `profile = "flowcart"` in BOTH the backend block AND the data.terraform_remote_state.bootstrap config block.

### Step 2: Validate

```bash
terraform validate
```

Expected: `Success! The configuration is valid.`

### Step 3: Plan

```bash
terraform plan -out=shared.tfplan
```

Read the output carefully. You should see roughly:
- **0 to import**
- **~25 resources to add**
- **0 to change**
- **0 to destroy**

Resources you should see:
- 5x `aws_ecr_repository.service`
- 5x `aws_ecr_lifecycle_policy.service`
- 5x `aws_ecr_repository_policy.cross_account_pull`
- 2x `aws_kms_key` + 2x `aws_kms_alias`
- 1x `aws_vpc.hub`
- 1x `aws_route53_zone.main`
- 1x `aws_iam_role.route53_cross_account` + policy
- 1x `aws_iam_openid_connect_provider.github`
- 1x `aws_iam_role.github_actions_entry` + policy

If the plan tries to destroy anything, **STOP** and investigate.

### Step 4: Apply

```bash
terraform apply shared.tfplan
```

Expected duration: **2–3 minutes**. KMS keys take the longest (~30 sec each).

### Step 5: Save outputs

```bash
terraform output > outputs.txt
cat outputs.txt
```

Note these values — Phase C will reference them:
- `ecr_repository_urls` (a map — 5 URLs)
- `route53_zone_id`
- `github_oidc_provider_arn`
- `github_actions_entry_role_arn`
- `kms_secrets_key_arn`

## Verify it worked

### Check 1: ECR repos exist

```bash
aws ecr describe-repositories --profile flowcart-shared --query 'repositories[*].repositoryName' --output table
```

Should show 5 repos prefixed with `flowcart/`:

```
flowcart/catalog-service
flowcart/frontend
flowcart/notification-worker
flowcart/order-service
flowcart/payment-service
```

### Check 2: Route53 zone is private

```bash
aws route53 list-hosted-zones --profile flowcart-shared --query 'HostedZones[?Name==`flowcart.local.`]'
```

Should show one zone with `"PrivateZone": true`.

### Check 3: GitHub OIDC provider exists

```bash
aws iam list-open-id-connect-providers --profile flowcart-shared
```

Should include one ARN ending in `:oidc-provider/token.actions.githubusercontent.com`.

### Check 4: KMS keys

```bash
aws kms list-aliases --profile flowcart-shared --query 'Aliases[?starts_with(AliasName, `alias/flowcart`)]'
```

Should show `alias/flowcart-ecr` and `alias/flowcart-secrets`.

### Check 5: Cross-account ECR pull works

We can't actually test this until Phase C (when EKS exists), but we can verify the policy is attached:

```bash
aws ecr get-repository-policy \
  --repository-name flowcart/frontend \
  --profile flowcart-shared \
  --query 'policyText' --output text | jq
```

Should show a policy allowing `ecr:BatchGetImage` (and friends) for the Dev/Staging/Prod account roots.

## After Phase B

You now have the **supply chain foundation**:

- **Where images live**: ECR in Shared Services, immutable, encrypted, scanned
- **How CI auths to AWS**: GitHub OIDC, no long-lived keys
- **Where DNS records live**: Route53 private zone, ready for cross-account VPC associations
- **How secrets travel cross-account**: KMS secrets key, with workload accounts pre-granted use

This is the kind of foundation real production teams build in their first sprint after AWS Organizations setup. You've done it in 2 days. Good.

## Troubleshooting

### "Error: error creating ECR repository: KMSAccessDeniedException"

KMS key isn't fully provisioned yet. AWS sometimes returns "ready" for KMS before it's actually usable. Wait 30 seconds and re-run `terraform apply`.

### "Error: AccessDenied when assuming OrganizationAccountAccessRole"

Same as Day 1: your shell probably has stale AWS_* environment variables. Run `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE` and try again.

### "Error: error creating IAM OpenID Connect Provider: EntityAlreadyExists"

Means you already created the OIDC provider manually or in a previous run. Import it:

```bash
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::596451157598:oidc-provider/token.actions.githubusercontent.com
```

Then re-run plan; it should show no changes for that resource.

### "Error: route53 zone vpc.0.vpc_id must be set"

Means the hub VPC creation failed earlier. Check VPC quota in Shared Services — AWS has a default 5-VPC limit per region. If exceeded, request quota increase or clean up unused VPCs.

## What's next: Day 3 — Phase B Dev Infrastructure

Day 3 builds the Dev environment's foundation in the Dev account (163081954053):

- VPC with 3-tier subnets (public/private/intra) across 3 AZs
- VPC endpoints (S3, ECR, KMS — keeps traffic on AWS backbone)
- RDS Postgres 16 (single-AZ for dev cost)
- ElastiCache Redis 7.1
- SQS queue + DLQ
- VPC association to the flowcart.local zone (cross-account dance)
- IAM roles: GitHubActionsDeployer, TerraformDeployer

That's bigger than Day 2. Plan 2–3 hours for it.
