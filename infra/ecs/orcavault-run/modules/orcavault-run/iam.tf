# The ECS execution role and policies.

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The role for the dbt task, which connects to the database as a `IAMR:<role_name>` user.
resource "aws_iam_role" "dbt_task" {
  name               = "${local.name_prefix}-dbt-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "dbt_task" {
  statement {
    sid       = "RedshiftIamAuth"
    effect    = "Allow"
    actions   = ["redshift-serverless:GetCredentials"]
    resources = [data.aws_redshiftserverless_workgroup.this.arn]
  }

  statement {
    sid    = "ReadCatalog"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:SearchTables",
      "lakeformation:GetDataAccess",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ListCdcFiles"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [data.aws_s3_bucket.cdc.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.cdc_s3_prefix}*"]
    }
  }

  statement {
    sid       = "ReadCdcFiles"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.cdc.arn}/${var.cdc_s3_prefix}*"]
  }

  statement {
    sid       = "LocateCdcBucket"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation"]
    resources = [data.aws_s3_bucket.cdc.arn]
  }

  statement {
    sid       = "WriteRunEvent"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.results.arn}/${local.results_prefix}*/event.json"]
  }
}

resource "aws_iam_role_policy" "dbt_task" {
  name   = "${local.name_prefix}-dbt-task-policy"
  role   = aws_iam_role.dbt_task.id
  policy = data.aws_iam_policy_document.dbt_task.json
}

# The policy and associated role defined for the Step Functions.
# See https://docs.aws.amazon.com/step-functions/latest/dg/ecs-iam.html
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
    sid       = "RunDbtTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.dbt.arn_without_revision}:*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  statement {
    sid       = "WatchDbtTask"
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks", "ecs:StopTask"]
    resources = ["arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.this.name}/*"]
  }

  # Used to check that no other run is going.
  statement {
    sid       = "ListDbtTasks"
    effect    = "Allow"
    actions   = ["ecs:ListTasks"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  # Required for the .sync integration wait.
  statement {
    sid       = "SyncRule"
    effect    = "Allow"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }

  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_execution.arn, aws_iam_role.dbt_task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Allows reading the run event afterwards.
  statement {
    sid       = "ReadRunEvent"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.results.arn}/${local.results_prefix}*/event.json"]
  }

  # This is also needed to avoid errors when an event is missing or wasn't written
  # properly.
  statement {
    sid       = "ListRunResults"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn]
  }

  statement {
    sid       = "SendRunEvent"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/default"]
  }
}

resource "aws_iam_role_policy" "states" {
  name   = "${local.name_prefix}-states-policy"
  role   = aws_iam_role.states.id
  policy = data.aws_iam_policy_document.states.json
}

# This defines the policy and role for the scheduler.
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
    resources = [aws_sfn_state_machine.run.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.name_prefix}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
