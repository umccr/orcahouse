locals {
  name_prefix = "orcahouse-notify-${var.environment}"
  # Warehouse account that owns the EventBridge rules. Pinned as a literal
  # (not aws_caller_identity) so the confused-deputy guard names the trusted
  # account explicitly, per design §10.1.
  account_id = "115253169271"
  region     = "ap-southeast-2"
}

# Trust policy: allow EventBridge to assume the publisher role, with
# confused-deputy protection scoping it to this account and this
# environment's notification rules only.
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
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Inline policy: sns:Publish on this environment's Slack topic only.
# No KMS permissions are granted — the Slack topics are treated as
# unencrypted / not customer-managed-key (issue note U-11). If a topic
# were encrypted with a CMK, this role would also need kms:GenerateDataKey*
# and kms:Decrypt on that key, and the key policy would have to allow it.
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
