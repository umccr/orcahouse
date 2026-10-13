# This defines the dbt Fargate task and definition, which runs the orcavault runner inside
# the docker directory.

resource "aws_cloudwatch_log_group" "dbt" {
  name              = "/aws/ecs/${local.name_prefix}-dbt"
  retention_in_days = 90
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-dbt"
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = "${local.name_prefix}-dbt"
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.dbt_task.arn
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${data.aws_ecr_repository.dbt.repository_url}:${var.orcavault_release_ref}"
      essential = true

      environment = [
        { name = "ORCAVAULT_REDSHIFT_HOST", value = data.aws_redshiftserverless_workgroup.this.endpoint[0].address },
        { name = "ORCAVAULT_DBT_THREADS", value = tostring(var.dbt_threads) },
        { name = "ORCAVAULT_RESULTS_BUCKET", value = aws_s3_bucket.results.bucket },
      ]

      stopTimeout = 120

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dbt.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = local.container_name
        }
      }
    }
  ])
}
