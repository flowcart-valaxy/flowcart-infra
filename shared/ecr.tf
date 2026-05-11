# =============================================================================
# Amazon ECR Repositories
# =============================================================================
# One repository per microservice. All environments pull images from these.
# Cross-account access is granted via repository policy so Dev/Staging/Prod
# can pull images even though the repos live in Shared Services.
#
# Key design choices:
#   - Immutable tags: same tag never points to different content. Critical
#     for the build-once-promote-tag pattern in Phase F (Week 3).
#   - Scan on push: Trivy/inspector runs on every new image automatically.
#   - KMS encryption: images encrypted at rest with the ECR key in kms.tf.
#   - Lifecycle policy: keep 30 most recent tagged images, expire untagged
#     after 7 days. Without this, costs grow forever.
# =============================================================================

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = {
    Service = each.key
  }
}

# -----------------------------------------------------------------------------
# Lifecycle policy — applied to each repo
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last 30 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 30
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Cross-account pull policy
# -----------------------------------------------------------------------------
# Dev/Staging/Prod accounts need to PULL images from these repos. We grant
# this via a repository policy (resource-based) rather than IAM in each
# workload account (identity-based). Cleaner: trust statement lives WITH
# the resource being protected.

data "aws_iam_policy_document" "ecr_cross_account_pull" {
  statement {
    sid    = "AllowWorkloadAccountsPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = local.workload_account_arns
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
  }
}

resource "aws_ecr_repository_policy" "cross_account_pull" {
  for_each = aws_ecr_repository.service

  repository = each.value.name
  policy     = data.aws_iam_policy_document.ecr_cross_account_pull.json
}
