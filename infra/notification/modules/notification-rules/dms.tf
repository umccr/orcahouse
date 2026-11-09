# DMS Failure and LowStorage events, one rule (dms-<identifier>) per instance or task.
# DMS ARNs end in a generated ID, so each ARN is looked up by name and the name is written
# into its own rule's message. A replaced task or instance gets a new ARN: re-apply.

data "aws_dms_replication_instance" "this" {
  for_each = toset(var.dms_replication_instance_ids)

  replication_instance_id = each.key
}

data "aws_dms_replication_task" "this" {
  for_each = toset(var.dms_replication_task_ids)

  replication_task_id = each.key
}

locals {
  # Keyed by the input identifiers, so the rule keys are known at plan time.
  dms_resources = merge(
    {
      for id in var.dms_replication_instance_ids : id => {
        arn  = data.aws_dms_replication_instance.this[id].replication_instance_arn
        kind = "replication instance"
      }
    },
    {
      for id in var.dms_replication_task_ids : id => {
        arn  = data.aws_dms_replication_task.this[id].replication_task_arn
        kind = "replication task"
      }
    },
  )

  dms_rules = {
    for id, r in local.dms_resources : "dms-${id}" => {
      description = "Send DMS Failure and LowStorage events for ${r.kind} ${id} to the Slack SNS topic"

      event_pattern = jsonencode({
        source = ["aws.dms"]
        detail = {
          category = ["Failure", "LowStorage"]
        }
        resources = [r.arn]
      })

      input_paths = {
        account      = "$.account"
        region       = "$.region"
        time         = "$.time"
        category     = "$.detail.category"
        eventType    = "$.detail.eventType"
        resourceLink = "$.detail.resourceLink"
      }

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] DMS <category>: ${id}"
          description = "*Process:* DMS CDC\n*Resource:* `${id}` (${r.kind})\n*Event:* <eventType>\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"
          nextSteps   = ["Console: <resourceLink>"]
          keywords    = ["OrcaHouse", var.environment, "dms"]
        }
      })
    }
  }
}
