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

# Exporting DB cluster data to Amazon S3
# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/export-cluster-data.html

resource "aws_kms_key" "aurora_export_key" {
  description             = "CMK for Aurora S3 export task encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "aurora_export_key_alias" {
  name          = "alias/aurora-export"
  target_key_id = aws_kms_key.aurora_export_key.id
}

resource "aws_iam_role" "aurora_export_role" {
  name        = "${local.stack_name}-rds-s3-export-role"
  description = "Allows Aurora RDS to export cluster data to S3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "export.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/export-cluster-data.Setup.html
resource "aws_iam_role_policy" "aurora_export_s3_policy" {
  name = "${local.stack_name}-rds-s3-export-policy"
  role = aws_iam_role.aurora_export_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject*",
          "s3:ListBucket",
          "s3:GetObject*",
          "s3:DeleteObject*",
          "s3:GetBucketLocation"
        ]
        Resource = [
          data.aws_s3_bucket.staging_data_bucket.arn,
          "${data.aws_s3_bucket.staging_data_bucket.arn}/*"
        ]
      },
      {
        Sid    = "KMSExportPolicy"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.aurora_export_key.arn
      }
    ]
  })
}

resource "aws_kms_key_policy" "aurora_export_key_policy" {
  key_id = aws_kms_key.aurora_export_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowWarehouseAccountToDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::115253169271:root"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# https://docs.aws.amazon.com/cli/latest/reference/rds/start-export-task.html
output "aurora_export_role_arn" {
  description = "IAM role ARN for Aurora S3 export — use in --iam-role-arn flag"
  value       = aws_iam_role.aurora_export_role.arn
}

output "aurora_export_kms_key_arn" {
  description = "CMK ARN for Aurora export task — use in --kms-key-id flag"
  value       = aws_kms_key.aurora_export_key.arn
}
