variable "project" { type = string }

data "aws_caller_identity" "current" {}

# CKV2_AWS_64 remediated — explicit KMS key policy. Without one, a key
# falls back to an implicit default policy that Checkov flags as
# insufficiently auditable/restrictive.
resource "aws_kms_key" "s3" {
  description             = "${var.project} S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EnableRootAccountAccess"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*"
    }]
  })

  tags = {
    Name = "${var.project}-s3-kms"
  }
}

#checkov:skip=CKV_AWS_144:Cross-region replication requires provisioning real infrastructure in a second AWS region — out of scope for this local-cluster project
resource "aws_s3_bucket" "access_logs" {
  bucket = "${var.project}-access-logs"

  tags = {
    Purpose = "S3 access log target"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CKV2_AWS_61 remediated — lifecycle rule expiring old noncurrent
# versions rather than retaining every version forever.
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_sns_topic" "access_logs_events" {
  name              = "${var.project}-access-logs-events"
  kms_master_key_id = aws_kms_key.s3.id
}

resource "aws_s3_bucket_notification" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  topic {
    topic_arn = aws_sns_topic.access_logs_events.arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }
}

#checkov:skip=CKV_AWS_144:Cross-region replication requires provisioning real infrastructure in a second AWS region — out of scope for this local-cluster project
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-artifacts"

  tags = {
    Purpose = "CI/CD artifacts and SBOMs"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "artifacts" {
  bucket        = aws_s3_bucket.artifacts.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "artifacts/"
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CKV2_AWS_62 remediated — SNS topic + event notification, so any
# object write to this bucket is observable, not just discoverable
# after the fact via a manual list.
resource "aws_sns_topic" "artifacts_events" {
  name              = "${var.project}-artifacts-events"
  kms_master_key_id = aws_kms_key.s3.id
}

resource "aws_s3_bucket_notification" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  topic {
    topic_arn = aws_sns_topic.artifacts_events.arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }
}

#checkov:skip=CKV_AWS_144:Cross-region replication requires provisioning real infrastructure in a second AWS region — out of scope for this local-cluster project
resource "aws_s3_bucket" "audit_logs" {
  bucket = "${var.project}-audit-logs"

  tags = {
    Purpose = "Falco and Vault audit output"
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "audit_logs" {
  bucket        = aws_s3_bucket.audit_logs.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "audit-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_sns_topic" "audit_logs_events" {
  name              = "${var.project}-audit-logs-events"
  kms_master_key_id = aws_kms_key.s3.id
}

resource "aws_s3_bucket_notification" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  topic {
    topic_arn = aws_sns_topic.audit_logs_events.arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "audit_logs_bucket" {
  value = aws_s3_bucket.audit_logs.id
}
