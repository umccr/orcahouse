# The roles for the Step Functions and the scheduler.

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
  # The crawlers, from the sfn-crawl module.
  source_policy_documents = compact([module.crawl.policy_json])

  statement {
    sid       = "CheckDmsTasks"
    effect    = "Allow"
    actions   = ["dms:DescribeReplicationTasks"]
    resources = ["*"]
  }

  statement {
    sid       = "FindGlueJobs"
    effect    = "Allow"
    actions   = ["glue:ListJobs"]
    resources = ["*"]
  }

  # Only this environment's OrcaGlue jobs, even if a job from the other one is tagged.
  # See https://docs.aws.amazon.com/step-functions/latest/dg/glue-iam.html
  statement {
    sid       = "RunGlueJobs"
    effect    = "Allow"
    actions   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = ["arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:job/${local.glue_job_name_prefix}*"]
  }

  statement {
    sid       = "SendSourcesEvent"
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

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.sources.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.name_prefix}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
