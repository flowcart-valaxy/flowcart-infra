# =============================================================================
# terraform.tfvars - YOUR ENVIRONMENT VALUES
# =============================================================================
# These are pre-filled for your specific AWS setup. If you ever rebuild from
# scratch with different account IDs, this is the only file you need to change.
# =============================================================================

project_name = "flowcart"
aws_region   = "us-east-1"

# Account IDs
management_account_id      = "631069968738"
shared_services_account_id = "596451157598"
dev_account_id             = "163081954053"
staging_account_id         = "749619032215"
prod_account_id            = "052750483328"

# OU IDs (from your AWS Organizations console)
shared_services_ou_id = "ou-w8el-twbyqroj"
workloads_ou_id       = "ou-w8el-xxr0tyw4"
production_ou_id      = "ou-w8el-f7ul5wi6"

# Local AWS CLI profile that has Management account credentials
aws_profile_management = "flowcart"
