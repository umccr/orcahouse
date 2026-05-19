terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/s3/landing-zone/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.45.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"

  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

# ---

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "lz" {
  bucket           = "orcahouse-landing-zone-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
  bucket_namespace = "account-regional"
  force_destroy    = false
}

resource "aws_s3_bucket_versioning" "lz" {
  bucket = aws_s3_bucket.lz.id

  versioning_configuration {
    status = "Disabled" # intentionally disabled the bucket versioning for iceberg purpose
  }
}

resource "aws_s3_bucket_public_access_block" "lz" {
  bucket                  = aws_s3_bucket.lz.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lz" {
  bucket = aws_s3_bucket.lz.id

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

    # Transition older data to cheaper storage
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
  }
}
