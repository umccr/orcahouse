# --- IAM Role for DMS

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "dms.amazonaws.com",
        "dms.ap-southeast-2.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "dms_compute" {
  name               = "${local.name_prefix}-dms-compute-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_vpc_management" {
  role       = aws_iam_role.dms_compute.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs" {
  role       = aws_iam_role.dms_compute.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}


# --- IAM Policy — DMS Access to Secrets Manager

data "aws_iam_policy_document" "dms_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [data.aws_secretsmanager_secret.source.arn]
  }
}

resource "aws_iam_role_policy" "dms_secrets_access" {
  name   = "${local.name_prefix}-dms-secrets-policy"
  role   = aws_iam_role.dms_compute.id
  policy = data.aws_iam_policy_document.dms_secrets_policy.json
}


# --- IAM Role for S3 Access

data "aws_iam_policy_document" "dms_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:AbortMultipartUpload",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      data.aws_s3_bucket.lz.arn,
      "${data.aws_s3_bucket.lz.arn}/*"
    ]
  }
}

resource "aws_iam_role" "dms_s3" {
  name               = "${local.name_prefix}-dms-s3-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

resource "aws_iam_role_policy" "dms_s3" {
  name   = "${local.name_prefix}-dms-s3-policy"
  role   = aws_iam_role.dms_s3.id
  policy = data.aws_iam_policy_document.dms_s3.json
}


# --- The IAM Role arn:aws:iam:::role/dms-vpc-role
# AWS requires a special IAM role called dms-vpc-role when using this `aws_dms_replication_subnet_group` resource.
# See https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_subnet_group

resource "aws_iam_role" "dms_vpc_role" {
  name        = "dms-vpc-role"
  description = "Allows DMS to manage VPC"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}
