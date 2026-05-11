# =============================================================================
# Terraform State Bucket (in Shared Services account)
# =============================================================================
# Holds ALL Terraform state files for the entire project across all layers
# and environments. Lives in the Shared Services account.
#
# Bucket name pattern: <project>-tfstate-shared-<account-id>
# We append the account ID because S3 bucket names are GLOBALLY unique. Suffixing
# with the account ID guarantees no collision.
#
# Chicken-and-egg note:
#   - On the FIRST apply, this bucket is created using LOCAL state.
#   - After apply succeeds, you uncomment the backend block in versions.tf
#     and run `terraform init -migrate-state` to move the bootstrap state
#     into this bucket.
# =============================================================================

# -----------------------------------------------------------------------------
# The state bucket itself
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  provider = aws.shared
  bucket   = "${var.project_name}-tfstate-shared-${var.shared_services_account_id}"

  # Safety: prevent Terraform from accidentally destroying the state bucket.
  # If you ever genuinely need to delete it, remove this lifecycle block first.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is REQUIRED for state buckets. Lets you roll back to a previous
# state if something corrupts the file.
resource "aws_s3_bucket_versioning" "tfstate" {
  provider = aws.shared
  bucket   = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption. AES256 is fine for state; we'll use KMS for app data.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  provider = aws.shared
  bucket   = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block ALL public access. State files contain secrets; never expose.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  provider = aws.shared
  bucket   = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy: delete non-current versions after 90 days. State files
# accumulate versions on every apply; without cleanup, the bucket grows
# forever.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  provider = aws.shared
  bucket   = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}  # apply to all objects

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Abort multipart uploads that never finished (defensive)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# Cross-account access role for state
# -----------------------------------------------------------------------------
# Each environment account (Dev/Staging/Prod) needs read access to its own
# state file (and to read other layers' outputs via terraform_remote_state).
# The role below can be assumed from any account in the org.

data "aws_iam_policy_document" "tfstate_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        var.management_account_id,
        var.dev_account_id,
        var.staging_account_id,
        var.prod_account_id,
        var.shared_services_account_id,
      ]
    }
  }
}

data "aws_iam_policy_document" "tfstate_access" {
  # List all keys in the bucket
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  # Read/write/delete state files
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role" "tfstate_access" {
  provider           = aws.shared
  name               = "TerraformStateAccess"
  assume_role_policy = data.aws_iam_policy_document.tfstate_assume.json
}

resource "aws_iam_role_policy" "tfstate_access" {
  provider = aws.shared
  name     = "TerraformStateAccess"
  role     = aws_iam_role.tfstate_access.id
  policy   = data.aws_iam_policy_document.tfstate_access.json
}
