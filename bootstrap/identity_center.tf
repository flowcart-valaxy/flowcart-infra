# =============================================================================
# IAM Identity Center (formerly AWS SSO) — Permission Sets
# =============================================================================
# OPTIONAL: only managed by Terraform when var.enable_identity_center = true.
#
# Identity Center must be enabled MANUALLY in the AWS console first:
#   1. Sign in as ravi to the Management account
#   2. Go to IAM Identity Center service
#   3. Click "Enable" (one-time setup, takes 2-3 minutes)
#   4. Choose region matching var.aws_region
#   5. Set enable_identity_center = true in terraform.tfvars
#   6. Re-run terraform apply
#
# Why manual? Identity Center enable is a one-time, account-wide operation
# that AWS doesn't let you do via Terraform without significant workarounds.
# Once enabled, we manage permission sets via this file.
#
# This file is a no-op until you enable IC and flip the variable.
# =============================================================================

variable "enable_identity_center" {
  description = "Set to true AFTER you've enabled IAM Identity Center in the AWS console"
  type        = bool
  default     = false
}

data "aws_ssoadmin_instances" "current" {
  count = var.enable_identity_center ? 1 : 0
}

locals {
  sso_instance_arn = var.enable_identity_center ? tolist(data.aws_ssoadmin_instances.current[0].arns)[0] : ""
  sso_identity_id  = var.enable_identity_center ? tolist(data.aws_ssoadmin_instances.current[0].identity_store_ids)[0] : ""
}

# -----------------------------------------------------------------------------
# Permission Sets
# -----------------------------------------------------------------------------

# Admin: full access within an account (use for Dev/Staging)
resource "aws_ssoadmin_permission_set" "admin" {
  count            = var.enable_identity_center ? 1 : 0
  name             = "${var.project_name}-Admin"
  description      = "Full administrative access within the assigned account"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin[0].arn
}

# ReadOnly: for read-only access (use for Prod by default)
resource "aws_ssoadmin_permission_set" "readonly" {
  count            = var.enable_identity_center ? 1 : 0
  name             = "${var.project_name}-ReadOnly"
  description      = "Read-only access within the assigned account"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.readonly[0].arn
}

# Billing: for cost monitoring (use for Management account)
resource "aws_ssoadmin_permission_set" "billing" {
  count            = var.enable_identity_center ? 1 : 0
  name             = "${var.project_name}-Billing"
  description      = "Billing and cost management access"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "billing" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/Billing"
  permission_set_arn = aws_ssoadmin_permission_set.billing[0].arn
}

# -----------------------------------------------------------------------------
# NOTE: User and group assignments are NOT in Terraform.
#
# After applying this, go to the Identity Center console to:
#   1. Create a user for yourself (Users > Add user)
#   2. Assign that user to each account with the right permission set:
#      - Dev:       <project>-Admin
#      - Staging:   <project>-Admin
#      - Prod:      <project>-ReadOnly  (use console "Switch to Admin" via
#                                        break-glass role for write access)
#      - Mgmt:      <project>-Billing
#      - Shared:    <project>-Admin
#
# Why manual: for a solo learner, automating IC user assignments adds tons
# of code with little benefit. Real companies do it via Okta/Azure AD SCIM.
# -----------------------------------------------------------------------------
