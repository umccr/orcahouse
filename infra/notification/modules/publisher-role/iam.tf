locals {
  name_prefix = "orcahouse-notify-${var.environment}"
  # Pinned (not aws_caller_identity) so the trust policy names the account explicitly.
  account_id = "115253169271"
  region     = "ap-southeast-2"
}

# Only this environment's notification rules, in this account, may assume the role.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${local.region}:${local.account_id}:rule/${local.name_prefix}-*"]
    }
  }
}

resource "aws_iam_role" "publisher" {
  name               = "${local.name_prefix}-publisher-role"
  description        = "Assumed by EventBridge rules ${local.name_prefix}-* to publish alerts to the ${var.environment} Slack SNS topic"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# sns:Publish on this environment's Slack topic only. If the topic is ever encrypted with a
# customer-managed key, also allow kms:GenerateDataKey* and kms:Decrypt on that key.
data "aws_iam_policy_document" "publish" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.slack_topic_arn]
  }
}

resource "aws_iam_role_policy" "publish" {
  name   = "${local.name_prefix}-publisher-role-inline-policy"
  role   = aws_iam_role.publisher.id
  policy = data.aws_iam_policy_document.publish.json
}
