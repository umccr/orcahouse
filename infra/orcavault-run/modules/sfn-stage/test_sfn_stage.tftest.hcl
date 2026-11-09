mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-2"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  # The provider checks that these are ARNs where they're used.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-2:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:ap-southeast-2:123456789012:stateMachine:mock"
    }
  }
}

variables {
  environment     = "prod"
  name            = "sources"
  starter_service = "scheduler.amazonaws.com"

  definition = jsonencode({
    Comment       = "A stage under test."
    QueryLanguage = "JSONata"
    StartAt       = "DoIt"
    States        = { DoIt = { Type = "Succeed" } }
  })

  policy_statements = [{
    sid       = "CheckDmsTasks"
    actions   = ["dms:DescribeReplicationTasks"]
    resources = ["*"]
  }]

  source_policy_documents = ["{\"source\":\"from elsewhere\"}"]
}

run "the_states_role_does_its_own_work_and_the_common_things" {
  assert {
    condition = alltrue([
      for sid in ["CheckDmsTasks", "SendEvent", "DeliverLogs", "WriteLogs"] :
      contains([for statement in data.aws_iam_policy_document.states.statement : statement.sid], sid)
    ])
    error_message = "the states role should have the stage's own statements and the ones every stage needs"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.states.source_policy_documents) == 1
    error_message = "what the stage's states bring should be merged into its policy"
  }
}

run "each_role_is_assumed_by_one_service" {
  assert {
    condition = alltrue([
      for name, document in data.aws_iam_policy_document.assume :
      tolist(document.statement[0].principals)[0].type == "Service" &&
      contains(tolist(document.statement[0].condition)[0].values, "123456789012")
    ])
    error_message = "both roles should be assumed by one service in this account"
  }

  assert {
    condition = jsonencode({
      for name, document in data.aws_iam_policy_document.assume : name => tolist(tolist(document.statement[0].principals)[0].identifiers)[0]
    }) == jsonencode({ states = "states.amazonaws.com", start = "scheduler.amazonaws.com" })
    error_message = "the states role should be assumed by Step Functions and the other by the stage's starter"
  }
}

run "the_state_machine_logs_only_its_errors" {
  assert {
    condition     = aws_sfn_state_machine.this.name == "orcavault-run-prod-sources"
    error_message = "the state machine should be named after its environment and stage"
  }

  assert {
    condition = alltrue([
      aws_sfn_state_machine.this.logging_configuration[0].level == "ERROR",
      aws_sfn_state_machine.this.logging_configuration[0].include_execution_data == false,
    ])
    error_message = "only errors should be logged, without the execution's data"
  }

  assert {
    condition     = aws_cloudwatch_log_group.states.name == "/aws/vendedlogs/states/orcavault-run-prod-sources"
    error_message = "the logs should be the state machine's vended logs"
  }
}

run "nothing_starting_the_stage_alerts" {
  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.no_recent_success.alarm_name == "orcavault-run-prod-sources-no-recent-success",
      aws_cloudwatch_metric_alarm.no_recent_success.metric_name == "ExecutionsSucceeded",
      aws_cloudwatch_metric_alarm.no_recent_success.treat_missing_data == "breaching",
      aws_cloudwatch_metric_alarm.no_recent_success.evaluation_periods == var.max_hours_without_success,
    ])
    error_message = "a stage that hasn't succeeded for max_hours_without_success should alarm, missing data included"
  }
}

run "the_start_command_runs_the_stage_alone" {
  assert {
    condition     = endswith(output.start_command, "--input '{}'")
    error_message = "the command should run the stage on its own, without continuing the chain"
  }
}
