# =============================================================================
# Org-Level CloudTrail
# =============================================================================
# Captures every API call across ALL accounts in the organization and writes
# them to a single S3 bucket in Shared Services. This is the foundation of
# audit. Without it, you cannot investigate any incident.
#
# Cost note: CloudTrail mgmt events for the first trail per account are FREE.
# We're using one org-level trail, so cost is just S3 storage (~$0.50/mo for
# typical course usage).
# =============================================================================

# Note: the `aws_organizations_organization.org` resource in
# organization.tf also adds CloudTrail to aws_service_access_principals via
# its computed value (see organization.tf).

# -----------------------------------------------------------------------------
# S3 bucket for CloudTrail logs (in Shared Services account)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  provider = aws.shared
  bucket   = "${var.project_name}-cloudtrail-${var.shared_services_account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  provider = aws.shared
  bucket   = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  provider = aws.shared
  bucket   = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  provider = aws.shared
  bucket   = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move to Glacier after 90 days, delete after 365 days.
# CloudTrail logs are mostly cold storage — you query them rarely.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  provider = aws.shared
  bucket   = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "tier-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# -----------------------------------------------------------------------------
# Bucket policy that lets CloudTrail write
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_bucket" {
  # CloudTrail needs to check the bucket exists and ACLs
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  # CloudTrail needs to write log files
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.management_account_id}/*",
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  provider = aws.shared
  bucket   = aws_s3_bucket.cloudtrail.id
  policy   = data.aws_iam_policy_document.cloudtrail_bucket.json
}

# -----------------------------------------------------------------------------
# The Trail (in Management account, captures all org member accounts)
# -----------------------------------------------------------------------------

resource "aws_cloudtrail" "org" {
  name           = "${var.project_name}-org-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_organization_trail         = true   # captures events from ALL accounts
  is_multi_region_trail         = true   # captures events from ALL regions
  include_global_service_events = true   # IAM, Route53, etc.
  enable_log_file_validation    = true   # signed digests for tamper detection

  # Capture management events (default). Data events (S3 GetObject etc.) are
  # high-volume and expensive — we leave them off unless needed.
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_organizations_organization.org,
  ]
}
