# =============================================================================
# GitHub Actions OIDC Provider
# =============================================================================
# Federated identity so GitHub Actions workflows can assume AWS IAM roles
# WITHOUT storing any long-lived AWS credentials in GitHub secrets.
#
# Flow:
#   1. GitHub Actions workflow runs (in our org's repos)
#   2. GHA issues an OIDC token (signed JWT) describing the workflow context
#      (repo, branch, environment, run ID, etc.)
#   3. The workflow calls sts:AssumeRoleWithWebIdentity using this token
#   4. AWS validates the token's signature + claims against this OIDC provider
#   5. AWS returns short-lived session credentials (15 min – 12 hours)
#   6. The assumed role can then chain-assume into env-specific deployer roles
#
# This is the modern, secure replacement for storing AWS_ACCESS_KEY_ID in
# GitHub secrets. Long-lived AWS keys in CI is one of the top sources of
# cloud breaches. With OIDC, there's nothing to leak.
# =============================================================================

# -----------------------------------------------------------------------------
# The OIDC identity provider itself
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC certificate thumbprints. AWS also does library-side cert
  # chain validation now, so the thumbprint is less critical than it was
  # historically. Included for defense in depth.
  #
  # These two thumbprints cover both Cloudflare-signed and DigiCert-signed
  # paths. GitHub rotates between them.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Purpose = "GitHub Actions federated identity"
  }
}

# -----------------------------------------------------------------------------
# Entry role: GitHub Actions assumes this FIRST
# -----------------------------------------------------------------------------
# Trust policy is RESTRICTIVE. Two key conditions:
#   1. token.actions.githubusercontent.com:sub must match our repo pattern
#      (so forks/random repos can't assume the role)
#   2. token.actions.githubusercontent.com:aud must equal "sts.amazonaws.com"
#      (the OIDC audience claim — should match client_id_list above)

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Repo allowlist. The `:*` at the end means "any branch/PR/tag/env in
    # this repo". For tighter security we could lock to specific branches:
    #   repo:org/repo:ref:refs/heads/main
    # For now, any workflow in our 3 repos is allowed.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_repos : "repo:${var.github_org}/${repo}:*"]
    }

    # Audience must match the client_id we registered above
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions_entry" {
  name        = "GitHubActionsEntryRole"
  description = "Entry role for GitHub Actions OIDC federation. Chain-assumes into env-specific deployer roles."

  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# -----------------------------------------------------------------------------
# Entry role's permissions
# -----------------------------------------------------------------------------
# The entry role can:
#   - Chain-assume the GitHubActionsDeployer role in each workload account
#     (those roles don't exist yet — created in environments/<env>/infra/iam.tf)
#   - Push images to ECR (the entry role itself does the docker push)
#
# It CANNOT do anything else. Specifically: no S3, no EC2, no RDS access.
# All actual infrastructure changes happen via the chain-assumed deployer
# role in each workload account.

data "aws_iam_policy_document" "github_actions_chain_assume" {
  # Chain-assume into env deployer roles
  statement {
    sid     = "ChainAssumeDeployers"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::${var.dev_account_id}:role/GitHubActionsDeployer",
      "arn:aws:iam::${var.staging_account_id}:role/GitHubActionsDeployer",
      "arn:aws:iam::${var.prod_account_id}:role/GitHubActionsDeployer",
    ]
  }

  # ECR push permissions. The auth-token call must use "*" because ECR
  # auth tokens are account-wide, not repo-specific.
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [for r in aws_ecr_repository.service : r.arn]
  }

  # The KMS key used by ECR — required to push encrypted images
  statement {
    sid    = "ECRKMSEncrypt"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.ecr.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_chain_assume" {
  name   = "ChainAssumeAndECRPush"
  role   = aws_iam_role.github_actions_entry.id
  policy = data.aws_iam_policy_document.github_actions_chain_assume.json
}
