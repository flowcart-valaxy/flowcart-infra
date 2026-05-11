# =============================================================================
# Outputs — Shared Services Layer
# =============================================================================
# Values that downstream layers (environments/dev/*, etc.) consume via
# terraform_remote_state.
# =============================================================================

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for k, r in aws_ecr_repository.service : k => r.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value       = { for k, r in aws_ecr_repository.service : k => r.arn }
}

# -----------------------------------------------------------------------------
# Route53
# -----------------------------------------------------------------------------

output "route53_zone_id" {
  description = "Hosted zone ID for the primary domain"
  value       = aws_route53_zone.main.zone_id
}

output "route53_zone_name" {
  description = "Domain name of the primary zone"
  value       = aws_route53_zone.main.name
}

output "route53_zone_arn" {
  description = "ARN of the primary hosted zone"
  value       = aws_route53_zone.main.arn
}

output "route53_manager_role_arn" {
  description = "Role workload accounts assume to manage records in the shared zone"
  value       = aws_iam_role.route53_cross_account.arn
}

# -----------------------------------------------------------------------------
# GitHub OIDC
# -----------------------------------------------------------------------------

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (for trust policies in env accounts)"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_entry_role_arn" {
  description = "Role GitHub Actions assumes via OIDC before chain-assuming into env deployer roles"
  value       = aws_iam_role.github_actions_entry.arn
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

output "kms_ecr_key_arn" {
  description = "KMS key used for ECR image encryption"
  value       = aws_kms_key.ecr.arn
}

output "kms_secrets_key_arn" {
  description = "KMS key for cross-account secrets (Secrets Manager, SSM)"
  value       = aws_kms_key.secrets.arn
}

output "kms_secrets_key_alias" {
  description = "Alias for the secrets KMS key"
  value       = aws_kms_alias.secrets.name
}
