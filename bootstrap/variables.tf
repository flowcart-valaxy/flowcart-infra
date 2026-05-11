# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Project identity
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short, lowercase project name. Used in resource names everywhere."
  type        = string
  default     = "flowcart"
}

variable "aws_region" {
  description = "Primary AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# AWS account IDs (set in terraform.tfvars)
# -----------------------------------------------------------------------------
# These are the 12-digit account IDs you created manually via AWS Organizations.
# We pass them in as variables rather than discovering them dynamically because:
#   (a) it makes the dependency on existing infra explicit
#   (b) we can validate them before any apply
#   (c) it's how a senior team would do it in production

variable "management_account_id" {
  description = "AWS account ID of the Management (root) account"
  type        = string
  validation {
    condition     = length(var.management_account_id) == 12 && can(regex("^[0-9]+$", var.management_account_id))
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "shared_services_account_id" {
  description = "AWS account ID of the Shared Services account"
  type        = string
  validation {
    condition     = length(var.shared_services_account_id) == 12
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "dev_account_id" {
  description = "AWS account ID of the Dev account"
  type        = string
  validation {
    condition     = length(var.dev_account_id) == 12
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "staging_account_id" {
  description = "AWS account ID of the Staging account"
  type        = string
  validation {
    condition     = length(var.staging_account_id) == 12
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "prod_account_id" {
  description = "AWS account ID of the Prod account"
  type        = string
  validation {
    condition     = length(var.prod_account_id) == 12
    error_message = "Account ID must be exactly 12 digits."
  }
}

# -----------------------------------------------------------------------------
# OU IDs (set in terraform.tfvars)
# -----------------------------------------------------------------------------
# We pass these in because looking up an OU by name across many OUs is awkward
# in Terraform (the data source returns them all). Easier and clearer to wire
# the IDs explicitly.

variable "shared_services_ou_id" {
  description = "ID of the SharedServices OU (format: ou-XXXX-XXXXXXXX)"
  type        = string
}

variable "workloads_ou_id" {
  description = "ID of the Workloads OU"
  type        = string
}

variable "production_ou_id" {
  description = "ID of the Production OU"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS CLI profile
# -----------------------------------------------------------------------------

variable "aws_profile_management" {
  description = "AWS CLI profile to use for Management account API calls"
  type        = string
  default     = "flowcart"
}
