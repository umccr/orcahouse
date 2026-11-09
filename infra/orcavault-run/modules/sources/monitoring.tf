# This notifies if no sources execution has succeeded recently, which catches a schedule
# that stopped starting it. A degraded execution counts as succeeded.
resource "aws_cloudwatch_metric_alarm" "no_recent_success" {
  alarm_name        = "${local.name_prefix}-no-recent-success"
  alarm_description = "No OrcaVault ${var.environment} sources execution has succeeded in the last ${var.max_hours_without_success} hours."

  namespace   = "AWS/States"
  metric_name = "ExecutionsSucceeded"
  dimensions = {
    StateMachineArn = aws_sfn_state_machine.sources.arn
  }
  statistic = "Sum"
  period    = 3600

  evaluation_periods  = var.max_hours_without_success
  datapoints_to_alarm = var.max_hours_without_success
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
}
