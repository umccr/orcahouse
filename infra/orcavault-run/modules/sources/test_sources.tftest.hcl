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

run "only_the_upstream_cdc_crawlers_are_included" {
  assert {
    condition = jsonencode(var.cdc_crawler_names) == jsonencode([
      "orcabus-db-crawler-case-manager",
      "orcabus-db-crawler-filemanager",
      "orcabus-db-crawler-metadata-manager",
      "orcabus-db-crawler-sequence-run-manager",
      "orcabus-db-crawler-workflow-manager",
    ])
    error_message = "the stage should crawl the upstream orcabus-db crawlers, and no others"
  }

  assert {
    condition = jsonencode(var.dms_replication_task_ids) == jsonencode([
      "orcabus-db-task-case-manager",
      "orcabus-db-task-filemanager",
      "orcabus-db-task-metadata-manager",
      "orcabus-db-task-sequence-run-manager",
      "orcabus-db-task-workflow-manager",
    ])
    error_message = "the DMS tasks to check should be the ones writing this CDC"
  }
}

run "the_cdc_is_checked_then_crawled" {
  assert {
    condition     = jsondecode(local.definition).StartAt == "CheckDms"
    error_message = "the execution should start by checking the DMS tasks"
  }

  assert {
    condition     = jsondecode(local.definition).States.CheckDms.Next == "CrawlCdc"
    error_message = "the crawls should follow the DMS check, whatever it found"
  }

  assert {
    condition     = jsonencode(jsondecode(local.definition).States.CrawlCdc.Items) == jsonencode(var.cdc_crawler_names)
    error_message = "every CDC crawler should be crawled"
  }

  assert {
    condition = alltrue([
      jsondecode(local.definition).States.CrawlCdc.Next == "AddRunFields",
      jsondecode(local.definition).States.CrawlCdc.Catch[0].Next == "AddRunFields",
    ])
    error_message = "every execution should send its event"
  }
}

run "a_failed_source_is_reported" {
  assert {
    condition = alltrue([
      for state in [
        jsondecode(local.definition).States.CheckDms,
        jsondecode(local.definition).States.CrawlCdc,
      ] : state.Catch[length(state.Catch) - 1].ErrorEquals == ["States.ALL"]
    ])
    error_message = "a failed DMS check or crawl should be reported, not fail the stage"
  }

  assert {
    condition     = contains(local.succeeded_outcomes, "degraded")
    error_message = "a stale source should not fail the execution"
  }
}

run "environments_are_separate" {
  variables {
    environment = "dev"
  }

  assert {
    condition = alltrue([
      for name in [
        module.stage.state_machine_name,
        module.stage.log_group_name,
        module.stage.states_role_name,
        module.stage.alarm_name,
        aws_scheduler_schedule.daily.name,
      ] : startswith(name, "orcavault-run-dev-") || startswith(name, "/aws/vendedlogs/states/orcavault-run-dev-")
    ])
    error_message = "everything an environment creates should be named after it"
  }
}
