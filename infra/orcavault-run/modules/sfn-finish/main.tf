# The states that end every OrcaVault stage. They add the fields that every stage's event
# has, send the event, and finish the execution with its outcome. A stage assigns $detail,
# which has at least outcome and error, and goes to AddRunFields. This module only creates
# states, not resources.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  region               = data.aws_region.current.region
  execution_url_prefix = "https://${local.region}.console.aws.amazon.com/states/home?region=${local.region}#/v2/executions/details/"

  # The fields every stage's event has. downstream is true only when the execution was
  # started with {"downstream": true}, which is what the next stage's rule matches on.
  fields = merge({
    environment     = jsonencode(var.environment)
    runId           = "$states.context.Execution.Name"
    downstream      = "$states.context.Execution.Input.downstream = true"
    durationMinutes = "$round(($millis() - $toMillis($states.context.Execution.StartTime)) / 60000)"
    executionUrl    = "'${local.execution_url_prefix}' & $states.context.Execution.Id"
  }, var.extra_fields)

  with_fields = "{% $merge([$detail, {${join(", ", [for name, expression in local.fields : "'${name}': ${expression}"])}}]) %}"

  states = {
    AddRunFields = {
      Type    = "Pass"
      Comment = "Adds the fields every event has."
      Assign  = { detail = local.with_fields }
      Next    = "SendEvent"
    }

    SendEvent = {
      Type     = "Task"
      Resource = "arn:aws:states:::events:putEvents"
      Arguments = {
        Entries = [
          {
            EventBusName = "default"
            Source       = var.event_source
            DetailType   = var.event_detail_type
            Detail       = "{% $detail %}"
          }
        ]
      }
      Output = {}
      Retry = [
        {
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 10
          MaxAttempts     = 3
          BackoffRate     = 2
        }
      ]
      # The execution still ends with the outcome, so that the no-success alarm doesn't
      # count a failed stage.
      Catch = [
        {
          ErrorEquals = ["States.ALL"]
          Next        = "Finish"
        }
      ]
      Next = "Finish"
    }

    Finish = {
      Type = "Choice"
      Choices = [
        {
          Condition = "{% $detail.outcome in ${jsonencode(var.succeeded_outcomes)} %}"
          Next      = "Succeeded"
        }
      ]
      Default = "Failed"
    }

    Succeeded = {
      Type   = "Succeed"
      Output = "{% $detail %}"
    }

    Failed = {
      Type  = "Fail"
      Error = "{% $detail.outcome %}"
      Cause = "{% ${var.failed_cause} %}"
    }
  }
}
