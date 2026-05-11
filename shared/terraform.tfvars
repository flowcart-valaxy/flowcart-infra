# =============================================================================
# terraform.tfvars — Shared Services Layer
# =============================================================================

project_name           = "flowcart"
aws_region             = "us-east-1"
aws_profile_management = "flowcart"

# Account IDs (must match what's in Phase A)
shared_services_account_id = "596451157598"
dev_account_id             = "163081954053"
staging_account_id         = "749619032215"
prod_account_id            = "052750483328"

# Domain configuration
domain_name      = "flowcart.local"
use_private_zone = true   # .local domains MUST be private

# GitHub configuration — change if you renamed the org
github_org   = "ravi-flowcart"
github_repos = ["flowcart-infra", "flowcart-platform", "flowcart-apps"]

# Services (5 microservices in the course)
service_names = [
  "frontend",
  "catalog-service",
  "order-service",
  "payment-service",
  "notification-worker",
]
