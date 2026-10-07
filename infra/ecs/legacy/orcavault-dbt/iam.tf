# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html

data "aws_iam_policy_document" "ecs_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_ssm_parameter" "orcavault_dbt_username" {
  # name = "/${local.stack_name}/${local.database_name}/dbt_username"

  # FIXME
  #  yet to provision dbt db user with aurora-su stack.
  #  just using master for now. early days.
  name = "/orcahouse/master"
}

data "aws_secretsmanager_secret" "orcavault_dbt" {
  # FIXME see above^
  # name = "${local.stack_name}/${local.database_name}/${data.aws_ssm_parameter.orcavault_dbt_username.value}"
  name = data.aws_ssm_parameter.orcavault_dbt_username.value
}

data "aws_iam_policy_document" "this" {
  statement {
    actions = sort([
      "secretsmanager:GetSecretValue",
    ])
    resources = sort([
      data.aws_secretsmanager_secret.orcavault_dbt.arn
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

# NOTE: making `this` role as both task and execution purpose to simplify thing a bit
resource "aws_iam_role" "this" {
  name               = "${local.stack_name}-${local.database_name}-dbt-ecs-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_policy.json
}

resource "aws_iam_role_policy" "this" {
  name   = "${local.stack_name}-${local.database_name}-dbt-ecs-role-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

# https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonECSTaskExecutionRolePolicy.html
resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
