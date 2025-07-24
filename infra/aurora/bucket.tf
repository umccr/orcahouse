# Allow import data from S3 to Aurora PostgreSQL
# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Integrating.html

variable "staging_bucket" {
  default = {
    dev  = "orcahouse-staging-data-843407916570"
    prod = "orcahouse-staging-data-472057503814"
    stg  = ""
  }
}

data "aws_s3_bucket" "staging_data_bucket" {
  bucket = var.staging_bucket[terraform.workspace]
}

data "aws_iam_policy_document" "rds_assume_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"

      values = [
        aws_rds_cluster.this.arn,
      ]
    }
  }
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid     = "s3import"
    effect  = "Allow"
    actions = sort([
      "s3:GetObject",
      "s3:ListBucket",
    ])
    resources = sort([
      data.aws_s3_bucket.staging_data_bucket.arn,
      "${data.aws_s3_bucket.staging_data_bucket.arn}/*"
    ])
  }
}

resource "aws_iam_role" "rds_s3_import_role" {
  name               = "${local.stack_name}-rds-s3-import-role"
  assume_role_policy = data.aws_iam_policy_document.rds_assume_policy.json
}

resource "aws_iam_role_policy" "rds_s3_policy" {
  name   = "${local.stack_name}-rds-s3-policy"
  role   = aws_iam_role.rds_s3_import_role.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_rds_cluster_role_association" "this" {
  db_cluster_identifier = aws_rds_cluster.this.id
  feature_name          = "s3Import"
  role_arn              = aws_iam_role.rds_s3_import_role.arn
}
