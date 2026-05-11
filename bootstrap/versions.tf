# =============================================================================
# Terraform & Provider Versions
# =============================================================================
# We pin Terraform >=1.13 because we use native S3 state locking (no DynamoDB
# table needed). AWS provider ~>6.0 is the current stable major.
# =============================================================================

terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # ---------------------------------------------------------------------------
  # IMPORTANT: backend block is commented out for the FIRST run.
  # The S3 bucket that holds Terraform state doesn't exist yet — this very
  # apply creates it. After the first successful apply:
  #
  #   1. Uncomment the block below
  #   2. Run: terraform init -migrate-state
  #   3. Type "yes" when prompted to copy local state to S3
  #   4. Delete the local terraform.tfstate file
  #
  # backend "s3" {
  #   bucket       = "flowcart-tfstate-shared-596451157598"
  #   key          = "shared/bootstrap/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true  # native S3 locking (TF 1.13+)
  #   assume_role = {
  #     role_arn = "arn:aws:iam::596451157598:role/OrganizationAccountAccessRole"
  #   }
  # }
}

# -----------------------------------------------------------------------------
# Default provider: Management account
# -----------------------------------------------------------------------------
# This provider uses your local AWS profile (the `flowcart` profile that has
# terraform-admin's credentials in the Management account). All Organizations
# resources (SCPs, CloudTrail, Identity Center) are created here.

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile_management

  default_tags {
    tags = {
      Project   = "flowcart"
      ManagedBy = "Terraform"
      Layer     = "bootstrap"
    }
  }
}

# -----------------------------------------------------------------------------
# Aliased provider: Shared Services account
# -----------------------------------------------------------------------------
# This provider assumes the OrganizationAccountAccessRole in the Shared
# Services account. We use it to create the Terraform state S3 bucket and
# any other resources that must live in Shared Services.

provider "aws" {
  alias   = "shared"
  region  = var.aws_region
  profile = var.aws_profile_management

  assume_role {
    role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "flowcart"
      ManagedBy = "Terraform"
      Layer     = "bootstrap"
    }
  }
}
