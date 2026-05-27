resource "aws_s3_bucket" "dev" {
  bucket           = "oncovault-dev-warehouse-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
  bucket_namespace = "account-regional"
  force_destroy    = false
}

resource "aws_s3_bucket_versioning" "dev" {
  bucket = aws_s3_bucket.dev.id

  versioning_configuration {
    status = "Disabled" # intentionally disabled the bucket versioning for iceberg purpose
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
  bucket = aws_s3_bucket.dev.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    # filter {
    #   prefix = "iceberg/"
    # }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # FIXME observe the usage pattern and configure transition rule
    # Transition older data to cheaper storage
    # transition {
    #   days          = 90
    #   storage_class = "STANDARD_IA"
    # }
    #
    # transition {
    #   days          = 365
    #   storage_class = "GLACIER_IR"
    # }
  }
}
