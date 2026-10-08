data "aws_iam_policy_document" "glue_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_s3_policy" {
  statement {
    actions = sort([
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ])
    resources = sort([
      data.aws_s3_bucket.glue_script_bucket.arn,
      "${data.aws_s3_bucket.glue_script_bucket.arn}/*"
    ])
  }

  statement {
    actions = sort([
      "secretsmanager:GetSecretValue",
    ])
    resources = sort([
      data.aws_secretsmanager_secret.orcavault_tsa.arn
    ])
  }

  statement {
    actions = sort([
      "ssm:GetParametersByPath",
      "ssm:GetParameters",
      "ssm:GetParameter",
    ])
    resources = ["*"]
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${local.stack_name}-glue-job-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_policy.json
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name   = "${local.stack_name}-glue-s3-policy"
  role   = aws_iam_role.glue_role.id
  policy = data.aws_iam_policy_document.glue_s3_policy.json
}

# Attach AWSGlueServiceRole policy for general GlueOps
# https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSGlueServiceRole.html
resource "aws_iam_role_policy_attachment" "ssm_instance_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
