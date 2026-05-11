# =============================================================================
# Outputs
# =============================================================================
# These values are consumed by:
#   (a) you, the operator — for reference when running future labs
#   (b) downstream layers — via terraform_remote_state
# =============================================================================

output "organization_id" {
  description = "AWS Organization ID"
  value       = data.aws_organizations_organization.current.id
}

output "organization_root_id" {
  description = "AWS Organization root ID"
  value       = data.aws_organizations_organization.current.roots[0].id
}

output "tfstate_bucket_name" {
  description = "S3 bucket holding all Terraform state files. Use this in backend blocks."
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_bucket_arn" {
  description = "ARN of the state bucket"
  value       = aws_s3_bucket.tfstate.arn
}

output "tfstate_access_role_arn" {
  description = "IAM role to assume for state file access (used in backend config)"
  value       = aws_iam_role.tfstate_access.arn
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket holding CloudTrail logs from all org accounts"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_arn" {
  description = "ARN of the org-level CloudTrail"
  value       = aws_cloudtrail.org.arn
}

output "scp_baseline_id" {
  description = "ID of the baseline SCP attached to org root"
  value       = aws_organizations_policy.baseline.id
}

output "scp_workloads_id" {
  description = "ID of the workloads SCP attached to Workloads + Production OUs"
  value       = aws_organizations_policy.workloads.id
}

output "scp_prod_id" {
  description = "ID of the prod-only SCP attached to Production OU"
  value       = aws_organizations_policy.prod.id
}

output "account_ids" {
  description = "All account IDs for reference"
  value = {
    management      = var.management_account_id
    shared_services = var.shared_services_account_id
    dev             = var.dev_account_id
    staging         = var.staging_account_id
    prod            = var.prod_account_id
  }
}

output "sso_instance_arn" {
  description = "IAM Identity Center instance ARN (empty if not enabled)"
  value       = local.sso_instance_arn
}
