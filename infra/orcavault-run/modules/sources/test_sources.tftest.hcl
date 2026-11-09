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
}

run "schedule_starts_the_chain" {
  assert {
    condition     = aws_scheduler_schedule.daily.state == "ENABLED"
    error_message = "the daily schedule should be enabled"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_scheduler_schedule.daily.target[0].input)) == jsonencode({ downstream = true })
    error_message = "the scheduled execution should continue the chain, {\"downstream\": true}"
  }
}

run "sources_load_together" {
  assert {
    condition     = length(jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches) == 2
    error_message = "the CDC and TSA sources should load in parallel"
  }

  assert {
    condition = alltrue([
      jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Next == "AddRunFields",
      jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Catch[0].Next == "AddRunFields",
    ])
    error_message = "every execution should send its event"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[0].States.CrawlCdc.Items) == jsonencode(var.cdc_crawler_names)
    error_message = "every CDC crawler should be crawled"
  }
}

run "a_failed_source_is_reported" {
  assert {
    condition = alltrue([
      for state in [
        jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[0].States.CheckDms,
        jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[1].States.FindGlueJobs,
        jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[1].States.RunGlueJobs.ItemProcessor.States.RunGlueJob,
      ] : state.Catch[length(state.Catch) - 1].ErrorEquals == ["States.ALL"]
    ])
    error_message = "a failed DMS check, job listing or job should be reported, not fail the stage"
  }

  assert {
    condition     = contains(local.succeeded_outcomes, "degraded")
    error_message = "a stale source should not fail the execution"
  }
}

run "only_this_environments_jobs_run" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[1].States.FindGlueJobs.Arguments.Tags) == jsonencode({ "orcahouse:pipeline-stage" = "sources" })
    error_message = "the jobs should be the ones tagged for this stage"
  }

  assert {
    condition     = strcontains(jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[1].States.FindGlueJobs.Output, "= 'orcaglue-dev-'")
    error_message = "only this environment's jobs should run"
  }

  assert {
    condition     = jsonencode(one([for statement in data.aws_iam_policy_document.states.statement : tolist(statement.resources) if statement.sid == "RunGlueJobs"])) == jsonencode(["arn:aws:glue:ap-southeast-2:123456789012:job/orcaglue-dev-*"])
    error_message = "the role should only run this environment's jobs"
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.sources.definition).States.LoadSources.Branches[1].States.RunGlueJobs.MaxConcurrency == 1
    error_message = "the jobs should run one at a time"
  }
}

run "environments_are_separate" {
  variables {
    environment = "dev"
  }

  assert {
    condition = alltrue([
      for name in [
        aws_sfn_state_machine.sources.name,
        aws_cloudwatch_log_group.states.name,
        aws_iam_role.states.name,
        aws_iam_role.scheduler.name,
        aws_scheduler_schedule.daily.name,
        aws_cloudwatch_metric_alarm.no_recent_success.alarm_name,
      ] : startswith(name, "orcavault-run-dev-") || startswith(name, "/aws/vendedlogs/states/orcavault-run-dev-")
    ])
    error_message = "everything an environment creates should be named after it"
  }
}
