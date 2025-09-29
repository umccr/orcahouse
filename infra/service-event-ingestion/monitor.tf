locals {
  # SNS topic linked to Chatbot for forwarding messages to Slack
  error_alarm_target = "arn:aws:sns:ap-southeast-2:472057503814:AwsChatBotTopic-alerts"
}

# ################################################################################
# Monitor Lambda functions for errors
# TODO: check if reporting together makes sense. Split otherwise.

module "lambda_error_alarms" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarms-by-multiple-dimensions"
  version = "~> 3.0"

  alarm_name          = "service_ingest_errors_"
  alarm_description   = "Lambda error rate is too high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 60
  unit                = "Count"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Maximum"

  dimensions = {
    "wmf_lambda" = {
      FunctionName = local.wfm.function_name
    },
    "fqr_lambda" = {
      FunctionName = local.fqr.function_name
    },
    "srm_sc_lambda" = {
      FunctionName = local.srm.sc_function_name
    },
    "srm_llc_lambda" = {
      FunctionName = local.srm.llc_function_name
    },
    "mm_lib_lambda" = {
      FunctionName = local.mm.lib_function_name
    }
  }

  alarm_actions = [local.error_alarm_target]
}

module "lambda_dlq_alarms" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarms-by-multiple-dimensions"
  version = "~> 3.0"

  alarm_name          = "service_ingest_dlq_"
  alarm_description   = "DLQ messages too high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 60
  unit                = "Count"

  namespace   = "AWS/SQS"
  metric_name = "NumberOfMessagesReceived"
  statistic   = "Maximum"

  dimensions = {
    "wfm_sqs" = {
      QueueName = "${local.wfm.function_name}_dlq"
    },
    "fqr_sqs" = {
      QueueName = "${local.fqr.function_name}_dlq"
    },
    "srm_sc_sqs" = {
      QueueName = "${local.srm.sc_function_name}_dlq"
    },
    "srm_llc_sqs" = {
      QueueName = "${local.srm.llc_function_name}_dlq"
    },
    "mm_lib_sqs" = {
      QueueName = "${local.mm.lib_function_name}_dlq"
    }
  }

  alarm_actions = [local.error_alarm_target]
}