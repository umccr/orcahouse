resource "aws_s3_bucket" "dev" {
  bucket           = "orcahouse-dev-cache-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
  bucket_namespace = "account-regional"
  force_destroy    = false
}

resource "aws_s3_bucket_versioning" "dev" {
  bucket = aws_s3_bucket.dev.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dev" {
  bucket = aws_s3_bucket.dev.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dev" {
  bucket                  = aws_s3_bucket.dev.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dev" {
  depends_on = [aws_s3_bucket.dev]
  bucket     = aws_s3_bucket.dev.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    # filter {
    #   prefix = "iceberg/"
    # }

    expiration {
      expired_object_delete_marker = true
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # TODO observe the bucket usage and add more rules to prefix
}
