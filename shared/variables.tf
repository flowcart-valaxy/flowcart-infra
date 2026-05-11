# =============================================================================
# Input Variables — Shared Services Layer
# =============================================================================

variable "project_name" {
  description = "Short, lowercase project name. Used in resource names."
  type        = string
  default     = "flowcart"
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile_management" {
  description = "AWS CLI profile pointing at the Management account"
  type        = string
  default     = "flowcart"
}

# -----------------------------------------------------------------------------
# Account IDs (pulled from bootstrap state OR set explicitly)
# -----------------------------------------------------------------------------
# We could read these from data.terraform_remote_state.bootstrap.outputs, but
# having them explicit in variables makes the layer's dependencies clearer
# and lets you run plan even if bootstrap state is inaccessible.

variable "shared_services_account_id" {
  description = "Shared Services account ID"
  type        = string
}

variable "dev_account_id" {
  description = "Dev account ID"
  type        = string
}

variable "staging_account_id" {
  description = "Staging account ID"
  type        = string
}

variable "prod_account_id" {
  description = "Prod account ID"
  type        = string
}

# -----------------------------------------------------------------------------
# Domain configuration
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Domain name. For a real domain use 'flowcart.io' (or similar). For learning, use 'flowcart.local'."
  type        = string
  default     = "flowcart.local"
}

variable "use_private_zone" {
  description = "true = private Route53 zone (for fake .local domains). false = public zone (for real domains)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# GitHub configuration
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organization or username that owns the repos"
  type        = string
  default     = "ravi-flowcart"
}

variable "github_repos" {
  description = "List of GitHub repositories that can assume the deployer role"
  type        = list(string)
  default = [
    "flowcart-infra",
    "flowcart-platform",
    "flowcart-apps",
  ]
}

# -----------------------------------------------------------------------------
# Services that need ECR repos
# -----------------------------------------------------------------------------

variable "service_names" {
  description = "Application services that need ECR repositories"
  type        = list(string)
  default = [
    "frontend",
    "catalog-service",
    "order-service",
    "payment-service",
    "notification-worker",
  ]
}
