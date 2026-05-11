# =============================================================================
# Route53 — Private Hosted Zone
# =============================================================================
# We use a PRIVATE hosted zone because flowcart.local is a fake domain (.local
# is reserved per RFC 6762 — it's not a real TLD, so a public zone would never
# resolve outside our VPCs).
#
# Why have a zone at all if we're not using real DNS?
#   1. Resources INSIDE our VPCs can resolve flowcart.local names via Route53
#      Resolver (the .2 IP in every VPC).
#   2. Practice the same DNS patterns you'd use with a real domain.
#   3. AWS LBC and external-dns work the same way whether the zone is public
#      or private — we get to learn the production pattern without the cost.
#
# Important: a private zone MUST be associated with at least one VPC. We
# create a tiny "hub" VPC in Shared Services purely to anchor the zone. Real
# workload VPCs (dev/staging/prod) will associate themselves to this zone
# later via cross-account VPC association.
#
# Cost: hub VPC has zero compute. ~$0/month.
# =============================================================================

# -----------------------------------------------------------------------------
# Hub VPC (tiny, only to anchor the private zone)
# -----------------------------------------------------------------------------

resource "aws_vpc" "hub" {
  cidr_block           = "10.0.0.0/24"   # tiny — 256 IPs total
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-hub-dns"
    Purpose = "Anchor private hosted zone for ${var.domain_name}"
  }
}

# -----------------------------------------------------------------------------
# The private hosted zone
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "${var.project_name} primary hosted zone (private)"

  vpc {
    vpc_id = aws_vpc.hub.id
  }

  # Tags for searchability
  tags = {
    Type = "private"
  }

  # Once VPCs from dev/staging/prod associate to this zone, Terraform on this
  # layer would otherwise try to disassociate them on every plan because they
  # weren't created here. lifecycle.ignore_changes on the vpc block keeps the
  # hub VPC managed by us and ignores cross-account additions.
  lifecycle {
    ignore_changes = [vpc]
  }
}

# -----------------------------------------------------------------------------
# VPC Association Authorization (for cross-account VPC association later)
# -----------------------------------------------------------------------------
# When the dev account's VPC wants to associate to this private zone (which
# lives in Shared Services), it needs PERMISSION from this side first.
#
# We can't pre-grant the authorization here because the workload VPCs don't
# exist yet — VPC IDs are required arguments. Instead, the dev infra layer
# will:
#   1. Create its VPC
#   2. Call aws_route53_vpc_association_authorization (in Shared Services)
#      via a cross-account provider
#   3. Call aws_route53_zone_association (in Dev) to actually associate
#
# So this file just creates the zone. Cross-account associations happen
# in environments/dev/infrastructure/route53_association.tf (next phase).

# -----------------------------------------------------------------------------
# Cross-account IAM role for Route53 management
# -----------------------------------------------------------------------------
# AWS Load Balancer Controller and ExternalDNS (when used) running in EKS
# clusters in workload accounts need to create A/CNAME records in this zone.
# Since the zone lives in Shared Services, they need cross-account access.

data "aws_iam_policy_document" "route53_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.workload_account_arns
    }
  }
}

data "aws_iam_policy_document" "route53_manage" {
  statement {
    sid    = "ManageRecords"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = [aws_route53_zone.main.arn]
  }

  statement {
    sid       = "GetChangeStatus"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid    = "ListZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "route53_cross_account" {
  name               = "${var.project_name}-Route53Manager"
  assume_role_policy = data.aws_iam_policy_document.route53_assume.json
  description        = "Assumed by AWS LBC and ExternalDNS in workload accounts to manage DNS records"
}

resource "aws_iam_role_policy" "route53_cross_account" {
  name   = "Route53Manage"
  role   = aws_iam_role.route53_cross_account.id
  policy = data.aws_iam_policy_document.route53_manage.json
}
