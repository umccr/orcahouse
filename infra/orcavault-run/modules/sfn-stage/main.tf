# The resources that every stage of the OrcaVault chain needs: its state machine and logs,
# the role its executions run as, the role that starts it, and an alarm for when nothing has
# started it recently. What a stage actually does is its own definition, which this module
# only deploys, see sources and publish.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45.0"
    }
  }
}

locals {
  name_prefix = "orcavault-run-${var.environment}-${var.name}"

  # Every stage ends by sending its event, see sfn-finish, so every states role can put to
  # the bus it publishes to.
  send_event_statement = {
    sid       = "SendEvent"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/default"]
  }

  # Step Functions sets up the state machine's log delivery as the states role, which needs
  # these on every resource, see https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html.
  deliver_logs_statement = {
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

  # The statements the states role always needs, plus whatever this stage does of its own.
  states_statements = concat(
    var.policy_statements,
    [local.send_event_statement, local.deliver_logs_statement, local.write_logs_statement],
  )

  write_logs_statement = {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.states.arn}:*"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}
