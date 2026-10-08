mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_redshiftserverless_workgroup" {
    defaults = {
      arn = "arn:aws:redshift-serverless:ap-southeast-2:123456789012:workgroup/orcahouse-prod"
      endpoint = [
        {
          address      = "orcahouse-prod.123456789012.ap-southeast-2.redshift-serverless.amazonaws.com"
          port         = 5439
          vpc_endpoint = []
        }
      ]
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

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-2:123456789012:mock"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:ap-southeast-2:123456789012:cluster/mock"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn                  = "arn:aws:ecs:ap-southeast-2:123456789012:task-definition/mock:1"
      arn_without_revision = "arn:aws:ecs:ap-southeast-2:123456789012:task-definition/mock"
    }
  }

  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:ap-southeast-2:123456789012:stateMachine:mock"
    }
  }
}

variables {
  orcavault_release_ref = "v1.0.0"
}

run "schedule_builds_everything" {
  assert {
    condition     = aws_scheduler_schedule.daily.state == "ENABLED"
    error_message = "the daily schedule should be enabled"
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.daily.target[0].input) == {}
    error_message = "the scheduled run should be the default request, {}"
  }
}

run "schedule_can_be_paused" {
  variables {
    schedule_enabled = false
  }

  assert {
    condition     = aws_scheduler_schedule.daily.state == "DISABLED"
    error_message = "the daily schedule should be disabled"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.no_recent_success.actions_enabled == false
    error_message = "the no recent success alarm should be quiet while the schedule is paused"
  }
}

run "every_run_sends_its_event" {
  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.RunDbt.Catch[0].Next == "ReadEvent"
    error_message = "a failed run should still read its event"
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.RunInProgress.Next == "SendEvent"
    error_message = "a skipped run should send its event"
  }

  assert {
    condition = alltrue([
      for state in ["CheckNoRunInProgress", "ReadEvent", "SendEvent"] :
      jsondecode(aws_sfn_state_machine.run.definition).States[state].Catch[0].ErrorEquals == ["States.ALL"]
    ])
    error_message = "every state after which the event could be lost should catch all errors"
  }

  assert {
    condition = alltrue([
      for detail in [
        jsondecode(aws_sfn_state_machine.run.definition).States.RunInProgress.Assign.detail,
        jsondecode(aws_sfn_state_machine.run.definition).States.CheckNoRunInProgress.Catch[0].Assign.detail,
        jsondecode(aws_sfn_state_machine.run.definition).States.ReadEvent.Catch[0].Assign.detail,
      ] : can(regex("\"error\":\"[^\"]+\"", detail))
    ])
    error_message = "an event the runner didn't write should still say why"
  }

  assert {
    condition     = strcontains(jsondecode(aws_sfn_state_machine.run.definition).States.ReadEvent.Arguments.Key, "'runs/' & $states.context.Execution.Name & '/event.json'")
    error_message = "the event should be read from where the runner writes it"
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.SendEvent.Arguments.Entries[0].Source == "orcahouse.orcavault"
    error_message = "unexpected event source"
  }
}

run "task_writes_its_event" {
  assert {
    condition = contains(
      jsondecode(aws_ecs_task_definition.dbt.container_definitions)[0].environment,
      { name = "ORCAVAULT_RESULTS_BUCKET", value = aws_s3_bucket.results.bucket },
    )
    error_message = "the task should be given the results bucket"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.dbt.container_definitions)[0].stopTimeout == 120
    error_message = "a stopped task should have time to write its event"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.results.rule[0].expiration).days == 90
    error_message = "events should expire after results_retention_days"
  }
}
