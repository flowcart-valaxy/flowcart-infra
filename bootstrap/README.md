# Day 1: Phase A — Bootstrap

This is the first Terraform you'll run for the flowcart project. It builds the **foundation** that everything else stacks on top of.

## What this creates

| Resource | Where | Why |
|---|---|---|
| 3 Service Control Policies (SCPs) | Management (Organizations) | Guardrails — even an Admin in a child account can't bypass these |
| Org-level CloudTrail | Management + Shared Services | Captures every API call across all 5 accounts. Audit foundation. |
| Terraform state S3 bucket | Shared Services | Where ALL future Terraform state lives. Versioned, encrypted. |
| Cross-account state access role | Shared Services | Lets Dev/Staging/Prod read their own state |
| (Optional) Identity Center permission sets | Management | SSO replacement for IAM users. Enable later if you want. |

## What this does NOT create

- AWS accounts, OUs, or org structure — you set those up manually (already done)
- VPCs, EKS clusters, RDS — those come in Day 2+
- IAM Identity Center itself — must be enabled manually (one-click in console)

## Prerequisites (you should already have these)

- [x] 5 AWS accounts created and placed in 3 OUs
- [x] AWS CLI configured with `flowcart` profile pointing at Management
- [x] `flowcart-shared`, `flowcart-dev`, `flowcart-staging`, `flowcart-prod` profiles working
- [x] Terraform 1.13+ installed locally
- [x] `terraform.tfvars` reviewed (values pre-filled for your environment)

Verify before starting:

```bash
terraform version              # must be 1.13.0 or higher
aws sts get-caller-identity --profile flowcart    # must show 631069968738
```

## Run order

### Step 1: Initialize Terraform with LOCAL backend

On the first run, we use local state because the S3 bucket doesn't exist yet (this run is creating it).

```bash
cd flowcart-infra/bootstrap
terraform init
```

You should see "Terraform has been successfully initialized!" with no errors.

> **Expected**: backend is "local" — that's correct for the first run.

### Step 2: Validate the configuration

```bash
terraform validate
```

Expected output: `Success! The configuration is valid.`

### Step 3: Plan

```bash
terraform plan -out=bootstrap.tfplan
```

Read the output carefully. You should see roughly:
- ~21 resources to be created
- 1 resource to be **imported** (your existing AWS Organization)
- 1 to be changed
- 0 to be destroyed

The import line will look like:
```
  # aws_organizations_organization.org will be imported
    resource "aws_organizations_organization" "org" {
        id = "o-XXXXXXXX"
        ...
    }
```

This is Terraform "adopting" your existing AWS Organization into its state — not creating a new one. This is the modern (Terraform 1.5+) pattern for managing pre-existing infrastructure.

Read the entire plan output. Notice:
- The import of `aws_organizations_organization.org`
- The 3 SCPs and their attachments
- The S3 buckets (state + cloudtrail) being created in Shared Services
- The CloudTrail resource
- The cross-account IAM role

If the plan tries to **destroy** anything, **STOP** and ask. Something's wrong.

### Step 4: Apply

```bash
terraform apply bootstrap.tfplan
```

Expected duration: **3–5 minutes**. Most of the time is waiting for SCPs to propagate and S3 buckets to materialize.

Watch the output. If anything fails, copy the error and we'll debug.

### Step 5: Save the outputs

```bash
terraform output > outputs.txt
cat outputs.txt
```

Note these values — you'll plug them into Day 2:
- `tfstate_bucket_name` (e.g., `flowcart-tfstate-shared-596451157598`)
- `tfstate_access_role_arn`

### Step 6: Migrate state from local → S3

Now the bucket exists. Move the bootstrap's own state into it so future applies use S3.

1. Open `versions.tf` in an editor
2. **Uncomment** the `backend "s3" { ... }` block (remove the leading `#` from each line)
3. Save the file
4. Run:

```bash
terraform init -migrate-state
```

Terraform will ask:

```
Initial configuration of the requested backend "s3"

Do you want to copy existing state to the new backend?
  Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

Type `yes` and press Enter.

5. After it succeeds, delete the local state file (it's been copied to S3):

```bash
rm terraform.tfstate terraform.tfstate.backup
```

### Step 7: Verify migration

Run plan again — it should still show "no changes" because the state is the same, just in a different place:

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

If you see this, **Phase A is done.** 🎉

## Verify it worked

### Check 1: SCPs attached

```bash
aws organizations list-policies-for-target \
  --target-id $(aws organizations list-roots --query 'Roots[0].Id' --output text --profile flowcart) \
  --filter SERVICE_CONTROL_POLICY \
  --profile flowcart
```

You should see `FullAWSAccess` (AWS default) **and** `flowcart-baseline-scp`.

### Check 2: State bucket exists

```bash
aws s3 ls --profile flowcart-shared | grep tfstate
```

Should show: `flowcart-tfstate-shared-596451157598`

### Check 3: CloudTrail is logging

Wait 10 minutes after apply, then:

```bash
aws s3 ls s3://flowcart-cloudtrail-596451157598/AWSLogs/ --profile flowcart-shared --recursive | head -5
```

Should show log files appearing. (CloudTrail batches events; first logs may take 5–15 minutes.)

### Check 4: SCP enforcement (FUN!)

Try to do something the prod SCP blocks. Switch into the Prod account in the console (Switch Role) and try to delete an EKS cluster (you don't have one, but the API call will be denied before the resource lookup):

```bash
aws eks delete-cluster --name fake-cluster --profile flowcart-prod
```

You should get an error like: `AccessDeniedException: ... explicit deny in a service control policy`.

**This is the SCP working as designed.** You just blocked a destructive action against prod, even though your IAM permissions in that account are full Admin.

## Optional: Enable IAM Identity Center

This step migrates you off long-lived IAM access keys to SSO sessions. Recommended but not required for the course.

1. Sign into the Management account (as ravi) in the AWS console
2. Go to **IAM Identity Center** service
3. Click **Enable** (one-click — takes 2-3 minutes)
4. Choose region: **us-east-1**
5. Edit `terraform.tfvars` — add this line:
   ```
   enable_identity_center = true
   ```
6. Re-run apply:
   ```bash
   terraform plan -out=ic.tfplan
   terraform apply ic.tfplan
   ```
7. In the Identity Center console:
   - Create a user (yourself)
   - Assign that user to each account with the appropriate permission set

After this, you can `aws sso login` instead of managing access keys.

## Troubleshooting

### Error: "The CALLER_ACCOUNT is not a delegated administrator"

You may need to register Shared Services as a delegated admin for some services. For now, the bootstrap doesn't need this — but if you see this error on a specific resource, ask for help.

### Error: "Cannot import resource X — already exists"

Means one of the resources Terraform wants to create is already in AWS (probably from a partial earlier run). Two options:

1. **Easier**: delete the existing resource manually in the console, then re-run apply
2. **Better practice**: `terraform import` the existing resource — but this is fiddly. Choose option 1 unless you're comfortable with imports.

### Error: "ConcurrentModificationException" on Organizations resources

AWS Organizations doesn't like parallel writes. Re-run the apply — it'll retry and succeed.

### State migration error: "Required backend configuration changed"

You may have forgotten to fully uncomment the backend block. Open `versions.tf` and make sure every line of `backend "s3" { ... }` is uncommented, including the closing `}`.

### Need to start over

If you want to completely reset and re-run:

```bash
terraform destroy
rm -rf .terraform terraform.tfstate*
```

Then start from Step 1 again. (Note: state bucket has `prevent_destroy = true` — you'll need to remove that lifecycle block first, OR delete the bucket manually in the console.)

## Cost

Phase A running idle: **~$1 per month** (CloudTrail S3 storage + state bucket storage). Effectively free.

## What's next: Day 2

Day 2 builds Phase B in the Shared Services account:
- ECR repos (5 of them)
- Route53 zones
- GitHub OIDC provider (for CI/CD later)
- KMS keys

Same pattern: per-folder Terraform, state in this bucket, deploy via `terraform apply`.
