# =============================================================================
# Service Control Policies (SCPs)
# =============================================================================
# SCPs are guardrails enforced at the AWS Organizations level. They cannot
# grant permissions — only restrict them. Even an Administrator in a child
# account cannot bypass an SCP.
#
# We define 3 policies of increasing strictness:
#   - baseline: applied to ALL accounts (security minimums everywhere)
#   - workloads: extra rules for Dev/Staging/Prod (no IAM users, region lock)
#   - prod: extra rules for Prod ONLY (block destructive ops outside CI roles)
#
# Order of attachment matters: more specific SCPs override less specific ones
# only when they restrict further. They CANNOT loosen restrictions.
# =============================================================================

# -----------------------------------------------------------------------------
# Baseline SCP
# -----------------------------------------------------------------------------
# Attached to the org Root, so it applies to every account including
# Management itself. Things that should NEVER happen anywhere in the org.

data "aws_iam_policy_document" "scp_baseline" {
  # 1. Cannot disable CloudTrail. Critical for audit.
  statement {
    sid    = "DenyCloudTrailDisable"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
    ]
    resources = ["*"]
  }

  # 2. Cannot disable GuardDuty (we'll enable this in Phase B).
  statement {
    sid    = "DenyGuardDutyDisable"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers",
      "guardduty:UpdateDetector",
    ]
    resources = ["*"]
  }

  # 3. Cannot leave the AWS Organization. Prevents account hijack scenarios.
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  # 4. Cannot disable AWS Config recording (we'll enable in Phase B).
  statement {
    sid    = "DenyConfigDisable"
    effect = "Deny"
    actions = [
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "baseline" {
  name        = "${var.project_name}-baseline-scp"
  description = "Baseline guardrails for all accounts in the org"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.scp_baseline.json

  # Must wait for SCPs to be enabled at the org level
  depends_on = [aws_organizations_organization.org]
}

resource "aws_organizations_policy_attachment" "baseline_root" {
  policy_id = aws_organizations_policy.baseline.id
  target_id = data.aws_organizations_organization.current.roots[0].id
}

# -----------------------------------------------------------------------------
# Workloads SCP
# -----------------------------------------------------------------------------
# Attached to the Workloads OU (Dev + Staging) AND the Production OU.
# Extra restrictions for workload accounts — no IAM user creation (force SSO),
# region lock to prevent surprise charges in other regions.

data "aws_iam_policy_document" "scp_workloads" {
  # 1. Region lock. The strongest cost-control SCP.
  # NotAction means "deny everything EXCEPT these listed actions, when the
  # request is outside our allowed region(s)". The whitelisted actions are
  # global services that have no region concept.
  statement {
    sid    = "DenyAllOutsideAllowedRegions"
    effect = "Deny"
    not_actions = [
      "iam:*",
      "organizations:*",
      "route53:*",
      "cloudfront:*",
      "globalaccelerator:*",
      "support:*",
      "sts:*",
      "kms:*",                # used by many services, awkward to region-lock
      "ec2:DescribeRegions",  # needed for AWS console to function
      "ec2:DescribeAccountAttributes",
      "health:*",
      "trustedadvisor:*",
      "tag:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # 2. Block IAM user/access-key creation in workload accounts.
  # Forces all human access to go through IAM Identity Center.
  statement {
    sid    = "DenyIAMUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "workloads" {
  name        = "${var.project_name}-workloads-scp"
  description = "Guardrails for workload accounts (Dev/Staging/Prod)"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.scp_workloads.json

  depends_on = [aws_organizations_organization.org]
}

# Attach to Workloads OU (Dev + Staging)
resource "aws_organizations_policy_attachment" "workloads_ou" {
  policy_id = aws_organizations_policy.workloads.id
  target_id = var.workloads_ou_id
}

# Attach to Production OU too (Prod gets BOTH the workloads SCP and the prod SCP)
resource "aws_organizations_policy_attachment" "workloads_prod_ou" {
  policy_id = aws_organizations_policy.workloads.id
  target_id = var.production_ou_id
}

# -----------------------------------------------------------------------------
# Prod SCP
# -----------------------------------------------------------------------------
# Attached to the Production OU only. Prevents destructive actions in Prod
# from anyone EXCEPT a specific CI deployer role.
#
# Important: this SCP doesn't block the TerraformDeployer role from doing
# its job, because we exclude it via the PrincipalARN condition. We'll
# create that role in Phase B.

data "aws_iam_policy_document" "scp_prod" {
  statement {
    sid    = "DenyDestructiveActionsOutsideDeployer"
    effect = "Deny"
    actions = [
      "rds:DeleteDBCluster",
      "rds:DeleteDBInstance",
      "rds:DeleteDBClusterSnapshot",
      "eks:DeleteCluster",
      "eks:DeleteNodegroup",
      "s3:DeleteBucket",
      "elasticache:DeleteReplicationGroup",
      "elasticache:DeleteCacheCluster",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalARN"
      values = [
        "arn:aws:iam::*:role/TerraformDeployer",
        "arn:aws:iam::*:role/BreakGlassAdmin",
      ]
    }
  }
}

resource "aws_organizations_policy" "prod" {
  name        = "${var.project_name}-prod-scp"
  description = "Strict guardrails for the Prod account"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.scp_prod.json

  depends_on = [aws_organizations_organization.org]
}

resource "aws_organizations_policy_attachment" "prod_ou" {
  policy_id = aws_organizations_policy.prod.id
  target_id = var.production_ou_id
}
