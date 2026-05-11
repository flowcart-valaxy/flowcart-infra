# =============================================================================
# KMS Keys
# =============================================================================
# Cross-account encryption keys. These live in the Shared Services account
# but are usable by Dev/Staging/Prod accounts via key policies.
#
# We create two keys:
#   - ECR encryption key: protects container images at rest
#   - Secrets encryption key: for Secrets Manager / SSM Parameter Store
#     (used later by External Secrets Operator from EKS)
#
# Cost: ~$1/month per key. We have 2 keys = ~$2/month.
# =============================================================================

locals {
  # Account IDs that need to use these keys (Dev/Staging/Prod)
  workload_account_ids = [
    var.dev_account_id,
    var.staging_account_id,
    var.prod_account_id,
  ]
  workload_account_arns = [for id in local.workload_account_ids : "arn:aws:iam::${id}:root"]
}

# -----------------------------------------------------------------------------
# KMS key for ECR image encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "ecr" {
  description             = "${var.project_name} ECR image encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Key policy: defines who can use the key.
  # The Shared Services account root has full admin. Workload accounts have
  # decrypt-only (so EKS nodes pulling images can decrypt them).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableSharedServicesRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.shared_services_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowWorkloadAccountsDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = local.workload_account_arns
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name    = "${var.project_name}-ecr"
    Purpose = "ECR image encryption"
  }
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.project_name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

# -----------------------------------------------------------------------------
# KMS key for secrets (Secrets Manager + SSM Parameter Store)
# -----------------------------------------------------------------------------
# External Secrets Operator (installed in Phase D) will use this key to
# decrypt secrets pulled into EKS clusters across environments.

resource "aws_kms_key" "secrets" {
  description             = "${var.project_name} secrets encryption (Secrets Manager, SSM)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableSharedServicesRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.shared_services_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowWorkloadAccountsUseKey"
        Effect = "Allow"
        Principal = {
          AWS = local.workload_account_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name    = "${var.project_name}-secrets"
    Purpose = "Cross-account secrets encryption"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
