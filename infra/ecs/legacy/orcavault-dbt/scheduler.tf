# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/scheduling_tasks.html
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tasks-scheduled-eventbridge-scheduler.html

data "aws_iam_policy_document" "scheduler_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler_policy" {
  # scheduler requires `ecs:RunTask` API call
  statement {
    actions = sort([
      "ecs:RunTask"
    ])
    resources = sort([
      trimsuffix(aws_ecs_task_definition.this.arn, ":${aws_ecs_task_definition.this.revision}")
    ])
  }

  # and, need to pass on any ecs task and execution roles
  statement {
    actions = sort([
      "iam:PassRole"
    ])
    resources = sort([
      aws_iam_role.this.arn
    ])
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.stack_name}-${local.database_name}-dbt-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_policy.json
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.stack_name}-${local.database_name}-dbt-scheduler-role-policy"
  policy = data.aws_iam_policy_document.scheduler_policy.json
  role   = aws_iam_role.scheduler.name
}

resource "aws_scheduler_schedule" "scheduler" {
  name       = "${local.stack_name}-${local.database_name}-dbt-scheduler"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"  # Run exactly at the scheduled time
  }

  schedule_expression = "cron(40 13 * * ? *)"  # Cron expression to run daily at 13:40 PM UTC = AEST/AEDT 00:40 AM
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.this.arn
    role_arn = aws_iam_role.scheduler.arn  # role that allows scheduler to start the task

    ecs_parameters {
      task_count = 1

      # trimming the revision suffix here so that schedule always uses latest revision
      task_definition_arn = trimsuffix(aws_ecs_task_definition.this.arn, ":${aws_ecs_task_definition.this.revision}")

      launch_type = "FARGATE"

      network_configuration {
        subnets          = data.aws_subnets.private_subnets.ids
        assign_public_ip = false

        security_groups = [
          local.orcahouse_db_sg_id[terraform.workspace]
        ]
      }
    }
  }
}
