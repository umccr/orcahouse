# The Step Functions definition that publishes the mart after a run, and the rule that
# starts it.

locals {
  # The event detail from the mart crawls.
  crawled_detail = replace(trimspace(<<-EOT
    {% (
      $failedCrawls := $states.result[status != 'SUCCEEDED'];
      {
        'outcome': $count($failedCrawls) > 0 ? 'degraded' : 'succeeded',
        'error': null,
        'crawlersSucceeded': $count($states.result[status = 'SUCCEEDED']),
        'crawlersFailed': $count($failedCrawls),
        'failedCrawlers': $join([$failedCrawls.(crawler & ' (' & status & ')')], ', ')
      }
    ) %}
  EOT
  ), "\n", " ")

  # The stage itself broke, rather than a crawl.
  error_detail = {
    outcome           = "error"
    error             = "Publishing the mart failed unexpectedly. Check the execution for details"
    crawlersSucceeded = 0
    crawlersFailed    = 0
    failedCrawlers    = ""
  }
}

resource "aws_cloudwatch_log_group" "states" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "publish" {
  name     = local.name_prefix
  role_arn = aws_iam_role.states.arn
  type     = "STANDARD"

  # Only errors are logged, without the execution's data, which its history has.
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.states.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment       = "Publishes the OrcaVault ${var.environment} mart after a run."
    QueryLanguage = "JSONata"
    StartAt       = "CrawlMart"

    States = merge(module.finish.states, {
      # Catalogs the mart for its readers, such as Athena through Lake Formation.
      CrawlMart = {
        Type          = "Map"
        Items         = module.crawl.items
        ItemProcessor = module.crawl.item_processor
        Assign        = { detail = local.crawled_detail }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Assign      = { detail = local.error_detail }
            Next        = module.finish.start_at
          }
        ]
        Next = module.finish.start_at
      }
    })
  })

  # Creating the state machine checks that the role can deliver its logs.
  depends_on = [aws_iam_role_policy.states]
}

# Starts publishing after a run that continues the chain, with {"downstream": true}.
resource "aws_cloudwatch_event_rule" "start" {
  name           = "${local.name_prefix}-start"
  description    = "Starts publishing the OrcaVault ${var.environment} mart after ${var.start_after.detail_type} with ${join(" or ", var.start_after.outcomes)}"
  event_bus_name = "default"

  event_pattern = jsonencode({
    source        = [var.start_after.source]
    "detail-type" = [var.start_after.detail_type]
    detail = {
      environment = [var.environment]
      downstream  = [true]
      outcome     = var.start_after.outcomes
    }
  })
}

resource "aws_cloudwatch_event_target" "start" {
  rule           = aws_cloudwatch_event_rule.start.name
  event_bus_name = "default"
  target_id      = "state-machine"
  arn            = aws_sfn_state_machine.publish.arn
  role_arn       = aws_iam_role.start.arn

  # The chain continues, so stages after this one start too.
  input = jsonencode({ downstream = true })

  # Retries starting the execution, not the stage itself.
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 5
  }
}
