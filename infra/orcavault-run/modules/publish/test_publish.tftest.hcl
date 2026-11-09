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
  environment = "prod"
  start_after = {
    source      = "orcahouse.orcavault"
    detail_type = "OrcaVaultRunFinished"
    outcomes    = ["succeeded", "warned"]
  }
}

run "runs_that_continue_the_chain_start_it" {
  assert {
    condition = jsonencode(jsondecode(aws_cloudwatch_event_rule.start.event_pattern).detail) == jsonencode({
      downstream  = [true]
      environment = ["prod"]
      outcome     = ["succeeded", "warned"]
    })
    error_message = "only this environment's applied runs that continue the chain should start publishing"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_cloudwatch_event_target.start.input)) == jsonencode({ downstream = true })
    error_message = "publishing should continue the chain, {\"downstream\": true}"
  }
}

run "every_execution_sends_its_event" {
  assert {
    condition     = jsondecode(aws_sfn_state_machine.publish.definition).States.Publish.Next == "AddRunFields"
    error_message = "every execution should send its event"
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.publish.definition).StartAt == "Publish"
    error_message = "the execution should end with the publish event"
  }
}

run "nothing_else_is_published_yet" {
  # The mart crawler keeps its own schedule, so this stage has no work of its own and
  # nothing that could make it degraded.
  assert {
    condition     = jsondecode(aws_sfn_state_machine.publish.definition).States.Publish.Type == "Pass"
    error_message = "the stage only carries the outcome to the event"
  }

  assert {
    condition     = !contains(local.outcomes, "degraded")
    error_message = "a stage with nothing to do cannot be degraded"
  }

  assert {
    condition     = !contains([for state in values(jsondecode(aws_sfn_state_machine.publish.definition).States) : state.Type], "Map")
    error_message = "the stage should crawl nothing"
  }
}

run "environments_are_separate" {
  variables {
    environment = "dev"
  }

  assert {
    condition = alltrue([
      for name in [
        aws_sfn_state_machine.publish.name,
        aws_iam_role.states.name,
        aws_iam_role.start.name,
        aws_cloudwatch_event_rule.start.name,
        aws_cloudwatch_metric_alarm.no_recent_success.alarm_name,
      ] : startswith(name, "orcavault-run-dev-")
    ])
    error_message = "everything an environment creates should be named after it"
  }
}
