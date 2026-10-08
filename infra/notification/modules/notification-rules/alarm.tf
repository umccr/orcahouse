# Forward orcahouse-notify-<env>-* CloudWatch alarms to Slack. Created in every
# environment. Alarms have no actions of their own. The alarm description becomes the
# message body and is inserted unescaped: no double quotes, and use the two characters
# \n for a line break (no other backslashes).
# alarm-resolved requires previousState ALARM, so a new alarm reaching OK does not post.

locals {
  alarm_name_prefix = "orcahouse-notify-${var.environment}-"

  alarm_input_paths = {
    account       = "$.account"
    region        = "$.region"
    time          = "$.time"
    alarmName     = "$.detail.alarmName"
    state         = "$.detail.state.value"
    previousState = "$.detail.previousState.value"
    description   = "$.detail.configuration.description"
  }

  alarm_console_link = "Console: https://<region>.console.aws.amazon.com/cloudwatch/home?region=<region>#alarmsV2:alarm/<alarmName>"
  alarm_description  = "<description>\n*State:* <state> (was <previousState>)\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"

  alarm_rules = {
    "alarm-firing" = {
      description = "Send ${local.alarm_name_prefix}* CloudWatch alarms entering ALARM to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["aws.cloudwatch"]
        "detail-type" = ["CloudWatch Alarm State Change"]
        detail = {
          alarmName = [{ prefix = local.alarm_name_prefix }]
          state     = { value = ["ALARM"] }
        }
      })

      input_paths = local.alarm_input_paths

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] Alarm: <alarmName>"
          description = local.alarm_description
          nextSteps   = [local.alarm_console_link]
          keywords    = ["OrcaHouse", var.environment, "alarm"]
        }
      })
    }

    "alarm-resolved" = {
      description = "Send ${local.alarm_name_prefix}* CloudWatch alarms returning from ALARM to OK to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["aws.cloudwatch"]
        "detail-type" = ["CloudWatch Alarm State Change"]
        detail = {
          alarmName     = [{ prefix = local.alarm_name_prefix }]
          state         = { value = ["OK"] }
          previousState = { value = ["ALARM"] }
        }
      })

      input_paths = local.alarm_input_paths

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":white_check_mark: [${var.environment}] Resolved: <alarmName>"
          description = local.alarm_description
          nextSteps   = [local.alarm_console_link]
          keywords    = ["OrcaHouse", var.environment, "alarm"]
        }
      })
    }
  }
}
