# =============================================================================
# AWS Organization, OUs, and Accounts (existing — referenced, not created)
# =============================================================================
# These are NOT created by Terraform — you set them up manually via the AWS
# Organizations console. This file uses data sources to reference them so we
# can attach SCPs, query account info, etc.
#
# Why not create them with Terraform? Two reasons:
#   1. AWS Organizations setup is a one-time, highly sensitive operation that
#      benefits from being done deliberately in the console.
#   2. Importing them into Terraform after-the-fact is fiddly. Senior teams
#      typically keep org-level structure out of Terraform.
# =============================================================================

# Pulls org metadata: ID, root ID, master account ID, feature set, etc.
data "aws_organizations_organization" "current" {}

# -----------------------------------------------------------------------------
# Import the existing org and update its config (idempotent)
# -----------------------------------------------------------------------------
# Your AWS Organization already exists (created manually). We need Terraform
# to "adopt" it so we can manage its policy_types and service_access_principals
# settings.
#
# The `import` block tells Terraform: "this resource already exists in AWS
# with this ID; don't create it, just attach it to our state."
#
# After the first successful apply, Terraform owns this resource and can
# update its settings going forward.

import {
  to = aws_organizations_organization.org
  id = data.aws_organizations_organization.current.id
}

resource "aws_organizations_organization" "org" {
  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "sso.amazonaws.com",
    "ram.amazonaws.com",
    "config.amazonaws.com",
  ]
}
