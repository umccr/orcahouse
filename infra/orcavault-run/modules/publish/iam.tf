# The roles for the Step Functions and the rule that starts it.

data "aws_iam_policy_document" "states_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "states" {
  name               = "${local.name_prefix}-states-role"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

data "aws_iam_policy_document" "states" {
  statement {
    sid       = "SendPublishEvent"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/default"]
  }

  # Step Functions sets up its log delivery as this role, which needs these on
  # every resource, see https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html.
  statement {
    sid    = "DeliverLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.states.arn}:*"]
  }
}

resource "aws_iam_role_policy" "states" {
  name   = "${local.name_prefix}-states-policy"
  role   = aws_iam_role.states.id
  policy = data.aws_iam_policy_document.states.json
}

data "aws_iam_policy_document" "start_assume" {
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
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "start" {
  name               = "${local.name_prefix}-start-role"
  assume_role_policy = data.aws_iam_policy_document.start_assume.json
}

data "aws_iam_policy_document" "start" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.publish.arn]
  }
}

resource "aws_iam_role_policy" "start" {
  name   = "${local.name_prefix}-start-policy"
  role   = aws_iam_role.start.id
  policy = data.aws_iam_policy_document.start.json
}
