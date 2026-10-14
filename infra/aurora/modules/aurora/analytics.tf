# Allow query Parquet, Iceberg, s3tables via aurora_analytics extension
# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-analytics-prerequisites.html

data "aws_iam_policy_document" "analytics_policy" {
  statement {
    effect = "Allow"
    actions = sort([
      "s3tables:ListTables",
      "s3tables:GetTableData",
      "s3tables:GetTableBucket",
      "s3tables:GetTable",
      "s3tables:GetNamespace",
      "s3:ListBucket",
      "s3:GetObject",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartitions",
      "glue:GetTable",
    ])
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "analytics_assume_policy" {
  statement {
    effect  = "Allow"
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

resource "aws_iam_role" "analytics_role" {
  name               = "${var.stack_name}-${var.environment}-aurora-analytics-role"
  assume_role_policy = data.aws_iam_policy_document.analytics_assume_policy.json
}

resource "aws_iam_role_policy" "analytics_policy" {
  name   = "${var.stack_name}-${var.environment}-aurora-analytics-policy"
  role   = aws_iam_role.analytics_role.id
  policy = data.aws_iam_policy_document.analytics_policy.json
}

# Obtain the feature_name like so:
#   aws rds describe-db-engine-versions --engine aurora-postgresql --engine-version 18.6
resource "aws_rds_cluster_role_association" "analytics" {
  db_cluster_identifier = aws_rds_cluster.this.id
  feature_name          = "AuroraAnalytics"
  role_arn              = aws_iam_role.analytics_role.arn
}
