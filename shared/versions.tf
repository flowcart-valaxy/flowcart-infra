# =============================================================================
# Terraform & Provider Versions — Shared Services Layer
# =============================================================================
# This layer's state lives in: shared/services/terraform.tfstate (in the same
# bucket created by Phase A bootstrap). The provider assumes
# OrganizationAccountAccessRole in the Shared Services account because all
# resources here belong to that account.
# =============================================================================

terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State backend — same bucket as bootstrap, different key
  backend "s3" {
    bucket       = "flowcart-tfstate-shared-596451157598"
    key          = "shared/services/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = "flowcart"
    assume_role = {
      role_arn = "arn:aws:iam::596451157598:role/OrganizationAccountAccessRole"
    }
  }
}

# -----------------------------------------------------------------------------
# Read Phase A bootstrap outputs
# -----------------------------------------------------------------------------
# We pull account IDs and other values from the bootstrap state instead of
# duplicating them as variables. Cross-layer state reads via
# terraform_remote_state is the senior pattern for keeping things DRY.

data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket       = "flowcart-tfstate-shared-596451157598"
    key          = "shared/bootstrap/terraform.tfstate"
    region       = "us-east-1"
    profile      = "flowcart"
    assume_role = {
      role_arn = "arn:aws:iam::596451157598:role/OrganizationAccountAccessRole"
    }
  }
}

# -----------------------------------------------------------------------------
# Default provider: Shared Services account
# -----------------------------------------------------------------------------
# All resources in this layer live in Shared Services. We assume into it
# from the Management profile.

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile_management

  assume_role {
    role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "flowcart"
      ManagedBy = "Terraform"
      Layer     = "shared"
    }
  }
}
