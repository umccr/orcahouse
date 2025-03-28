resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/ecs/${local.stack_name}-${local.database_name}-dbt"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "this" {
  name = "${local.stack_name}-${local.database_name}-dbt"
}

resource "aws_ecs_task_definition" "this" {
  family             = "${local.stack_name}-${local.database_name}-dbt"
  network_mode       = "awsvpc"
  cpu                = 4096
  memory             = 8192
  execution_role_arn = aws_iam_role.this.arn  # role that allows ECS to spin up your task, for example needs permission to ECR to get container image
  task_role_arn      = aws_iam_role.this.arn  # role that your workload gets to access AWS APIs

  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "orcavault-dbt"
      image     = "383856791668.dkr.ecr.ap-southeast-2.amazonaws.com/orcavault-dbt:latest"
      cpu       = 4096
      memory    = 8192
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "run"
        }
      }
      environment = [
        { "name" : "DB_HOST", "value" : data.aws_rds_cluster.orcahouse_db.endpoint },
        { "name" : "DB_NAME", "value" : local.database_name },
        { "name" : "SECRET_NAME", "value" : data.aws_secretsmanager_secret.orcavault_dbt.name },
        { "name" : "RO_USERNAME", "value" : data.aws_ssm_parameter.ro_username.value }
      ]
    }
  ])
}
