# --- The dbt task.
#
# Runs the umccr/orcavault project against Redshift Serverless. Step Functions
# starts it, see stepfunctions.tf. This replaces infra/ecs/legacy/orcavault-dbt,
# which runs the retired orcahouse/orcavault project against Aurora.

resource "aws_ecr_repository" "dbt" {
  name                 = "${local.name_prefix}-dbt"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "dbt" {
  repository = aws_ecr_repository.dbt.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last 20 images."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

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
      image     = "${aws_ecr_repository.dbt.repository_url}:${var.orcavault_release_ref}"
      essential = true

      # The first two are read by profiles.yml in the image. There is no
      # password: the task role is the credential. Step Functions adds the run
      # ID and the request to these, see stepfunctions.tf.
      environment = [
        { name = "ORCAVAULT_REDSHIFT_HOST", value = data.aws_redshiftserverless_workgroup.this.endpoint[0].address },
        { name = "ORCAVAULT_DBT_THREADS", value = tostring(var.dbt_threads) },
        { name = "ORCAVAULT_RESULTS_BUCKET", value = aws_s3_bucket.results.bucket },
      ]

      # A stopped run is given this long to let dbt cancel its queries and to
      # write its event. 120 seconds is the most Fargate allows. A task that's
      # still running then is killed, and the state machine sends the event.
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
