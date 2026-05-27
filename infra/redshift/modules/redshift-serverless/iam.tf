# Read the doc for tuning the permissions
#  https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-security-other-services.html
#  https://docs.aws.amazon.com/redshift/latest/mgmt/authorizing-redshift-service.html

###############################################################
# IAM Role for Redshift Serverless Namespace
###############################################################
data "aws_iam_policy_document" "namespace_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "redshift-serverless.amazonaws.com",
        "redshift.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "namespace" {
  name               = "${var.environment}-redshift-namespace-role"
  assume_role_policy = data.aws_iam_policy_document.namespace_assume.json

  tags = {
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "namespace_policy" {
  ###############################################################
  # Glue permissions
  ###############################################################
  statement {
    sid    = "GlueCatalogAccess"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:GetCatalogImportStatus",
    ]
    resources = var.glue_database_arns
  }

  ###############################################################
  # S3 permissions — read underlying Glue table data
  ###############################################################
  statement {
    sid    = "S3ReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = var.s3_bucket_arns
  }
}

resource "aws_iam_role_policy" "namespace" {
  name   = "${var.environment}-redshift-namespace-policy"
  role   = aws_iam_role.namespace.id
  policy = data.aws_iam_policy_document.namespace_policy.json
}
