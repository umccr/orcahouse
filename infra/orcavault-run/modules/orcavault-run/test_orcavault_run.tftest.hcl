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
  cdc_crawler_names       = ["orcabus-db-crawler-filemanager", "orcabus-db-crawler-workflow-manager"]
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

run "steps_define_runs" {
  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).StartAt == "ReadSteps" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ReadSteps.Assign.steps == "{% $exists($states.input.steps) ? $states.input.steps : [\"crawl\",\"dbt\"] %}"
    )
    error_message = "an execution without steps should do everything"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldCrawl.Choices[0].Next == "UnknownStep" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.UnknownStep.Type == "Fail"
    )
    error_message = "a step that doesn't exist should fail the execution"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldCrawl.Choices[1].Condition == "{% 'crawl' in $steps %}" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldCrawl.Choices[1].Next == "CrawlCdc" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldCrawl.Default == "ShouldRunDbt"
    )
    error_message = "the CDC should only be crawled when crawl is a step"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldRunDbt.Choices[0].Condition == "{% 'dbt' in $steps %}" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldRunDbt.Choices[0].Next == "CheckNoRunInProgress" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ShouldRunDbt.Default == "NoDbtStep" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.NoDbtStep.Default == "NoRun" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.NoRun.Type == "Succeed"
    )
    error_message = "dbt should only run when dbt is a step"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.NoDbtStep.Choices[0].Condition == "{% $crawlIncomplete != '' %}" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.NoDbtStep.Choices[0].Next == "CrawlIncomplete" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlIncomplete.Type == "Fail"
    )
    error_message = "an execution without dbt should fail if a crawl didn't finish, since it sends no event"
  }
}

run "the_run_crawls_the_cdc_first" {
  assert {
    condition     = jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.Next == "ShouldRunDbt"
    error_message = "the run should crawl the CDC before dbt"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.Items) == jsonencode(var.cdc_crawler_names)
    error_message = "the run should crawl every CDC crawler"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States.StartCrawler.Catch[0].ErrorEquals == ["Glue.CrawlerRunningException"] &&
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States.StartCrawler.Catch[0].Next == "WaitForCrawl"
    )
    error_message = "a crawl that is already running should wait"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States.StartCrawler.Retry[0].ErrorEquals == ["Glue.CrawlerRunningException"] &&
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States.StartCrawler.Retry[0].MaxAttempts == 0
    )
    error_message = "a crawl that is already running should be waited for without retrying the start"
  }

  assert {
    condition = alltrue([
      for name in ["StartCrawler", "GetCrawler"] : alltrue([
        for catch in jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States[name].Catch :
        jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States[catch.Next].Type == "Succeed" if catch.ErrorEquals == ["States.ALL"]
      ])
    ])
    error_message = "a crawl that can't be started or read shouldn't stop the run"
  }

  assert {
    condition = anytrue([
      for choice in jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States.IsCrawlDone.Choices :
      strcontains(choice.Condition, "> 3600000 %}") && choice.Next == "StillRunning"
    ])
    error_message = "the run should stop waiting for the crawls after crawl_max_wait_minutes"
  }

  assert {
    condition = alltrue([
      for name, state in jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.ItemProcessor.States :
      name == "Crawled" ? state.Output == "" : strcontains(state.Output, "$crawler & ' (") if state.Type == "Succeed"
    ])
    error_message = "every crawl that didn't finish should output its crawler and why"
  }

  assert {
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.ReadSteps.Assign.crawlIncomplete == "" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.CrawlCdc.Assign.crawlIncomplete == "{% $join($append([], $states.result[$ != '']), ', ') %}" &&
      jsondecode(aws_sfn_state_machine.run.definition).States.AddRunFields.Output.crawlIncomplete == "{% $crawlIncomplete %}"
    )
    error_message = "the run event should list the crawls that didn't finish"
  }

  assert {
    condition = (
      toset(one([for statement in data.aws_iam_policy_document.states.statement : statement.resources if statement.sid == "CrawlCdc"])) == toset(local.crawler_arns) &&
      alltrue([for i, name in var.cdc_crawler_names : endswith(local.crawler_arns[i], ":crawler/${name}")])
    )
    error_message = "the run should be able to start and read every CDC crawler"
  }
}

run "the_runner_gets_the_request" {
  assert {
    condition = one([
      for variable in jsondecode(aws_sfn_state_machine.run.definition).States.RunDbt.Arguments.Overrides.ContainerOverrides[0].Environment :
      variable.Value if variable.Name == "ORCAVAULT_RUN_REQUEST"
    ]) == "{% $string($states.context.Execution.Input ~> |$|{}, ['steps']|) %}"
    error_message = "the runner should get the execution input without steps"
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
    condition = (
      jsondecode(aws_sfn_state_machine.run.definition).States.ReadEvent.Catch[0].ErrorEquals == ["States.ALL"] &&
      jsondecode(aws_sfn_state_machine.run.definition).States.ReadEvent.Catch[0].Next == "AddRunFields"
    )
    error_message = "a run writing no event should send one"
  }

  assert {
    condition = jsondecode(aws_sfn_state_machine.run.definition).States.AddRunFields.Next == "SendEvent" && alltrue([
      for name, state in jsondecode(aws_sfn_state_machine.run.definition).States :
      name == "AddRunFields" || !contains(concat([try(state.Next, null)], [for catch in try(state.Catch, []) : catch.Next]), "SendEvent")
    ])
    error_message = "every event should have the fields of every run"
  }

  assert {
    condition     = try(jsondecode(aws_sfn_state_machine.run.definition).States.SendEvent.Catch, null) == null
    error_message = "an event that can't be sent should fail the execution, rather than be lost"
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

  assert {
    condition = anytrue([
      for statement in data.aws_iam_policy_document.dbt_task.statement :
      try(contains(statement.resources, "${aws_s3_bucket.results.arn}/*"), false)
    ])
    error_message = "the task should be able to write its event, manifest and run results"
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
