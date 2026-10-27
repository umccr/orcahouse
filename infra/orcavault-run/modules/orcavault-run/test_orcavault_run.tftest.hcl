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
  environment             = "prod"
  redshift_workgroup_name = "orcahouse-prod"
  orcavault_release_ref   = "v1.0.0"
  glue_databases          = ["orcabus_filemanager", "data_portal"]
  bucket_name             = "landing-zone"
  s3_prefix               = ["orcabus/v1/cdc/", "data-portal/export/"]
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

run "every_run_sends_its_event" {
  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.RunDbt.Catch[0].Next == "ReadEvent"
    error_message = "a failed run should still read its event"
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.RunInProgress.Next == "AddRunFields"
    error_message = "a skipped run should send its event"
  }

  assert {
    condition = jsondecode(aws_sfn_state_machine.run.definition).States.AddRunFields.Next == "SendEvent" && alltrue([
      for name, state in jsondecode(aws_sfn_state_machine.run.definition).States :
      name == "AddRunFields" || !contains(concat([try(state.Next, null)], [for catch in try(state.Catch, []) : catch.Next]), "SendEvent")
    ])
    error_message = "every event should have the fields of every run"
  }

  assert {
    condition = alltrue([
      for state in ["CheckNoRunInProgress", "ReadEvent", "SendEvent"] :
      jsondecode(aws_sfn_state_machine.run.definition).States[state].Catch[0].ErrorEquals == ["States.ALL"]
    ])
    error_message = "every state after the event is lost should catch errors"
  }

  assert {
    condition     = local.logs_url_prefix == "https://ap-southeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-2#logsV2:log-groups/log-group/$252Faws$252Fecs$252Forcavault-run-prod-dbt/log-events/dbt$252Fdbt$252F"
    error_message = "the logs URL should open the task's log stream"
  }

  assert {
    condition     = strcontains(jsondecode(aws_sfn_state_machine.run.definition).States.ReadEvent.Arguments.Key, "'runs/' & $states.context.Execution.Name & '/event.json'")
    error_message = "the event should be read from where the runner writes it"
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
}

run "task_reads_source" {
  assert {
    condition     = toset(keys(aws_lakeformation_permissions.cdc_tables)) == toset(var.glue_databases)
    error_message = "the task should be granted the tables of all database"
  }

  assert {
    condition = alltrue([
      for prefix in var.s3_prefix : anytrue([
        for statement in data.aws_iam_policy_document.dbt_task.statement :
        try(contains(statement.resources, "${data.aws_s3_bucket.cdc.arn}/${prefix}*"), false)
      ])
    ])
    error_message = "the task should be able to read the files"
  }

  assert {
    condition = alltrue([
      for prefix in var.s3_prefix : anytrue([
        for statement in data.aws_iam_policy_document.dbt_task.statement :
        try(contains(one(statement.condition).values, "${prefix}*"), false)
      ])
    ])
    error_message = "the task should be able to list the files under all prefixes"
  }
}

run "environments_are_separate" {
  variables {
    environment = "dev"
  }

  assert {
    condition = alltrue([
      for name in [
        aws_sfn_state_machine.run.name,
        aws_ecs_cluster.this.name,
        aws_ecs_task_definition.dbt.family,
        aws_cloudwatch_log_group.dbt.name,
        aws_s3_bucket.results.bucket,
        aws_iam_role.ecs_execution.name,
        aws_iam_role.dbt_task.name,
        aws_iam_role.states.name,
        aws_iam_role.scheduler.name,
        aws_scheduler_schedule.daily.name,
        aws_cloudwatch_metric_alarm.no_recent_success.alarm_name,
      ] : strcontains(name, "-dev")
    ])
    error_message = "everything an environment creates should be named after it"
  }
}
