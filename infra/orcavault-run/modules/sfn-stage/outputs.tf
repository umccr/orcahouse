output "state_machine_arn" {
  description = "The stage's state machine."
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "The stage's state machine name, which is what its executions are listed under."
  value       = aws_sfn_state_machine.this.name
}

output "start_role_arn" {
  description = "The role the schedule or rule that starts this stage assumes."
  value       = aws_iam_role.this["start"].arn
}

output "states_role_name" {
  description = "The role the stage's executions run as."
  value       = aws_iam_role.this["states"].name
}

output "log_group_name" {
  description = "The log group the stage's errors are delivered to."
  value       = aws_cloudwatch_log_group.states.name
}

output "alarm_name" {
  description = "The alarm for no recent successful execution of this stage."
  value       = aws_cloudwatch_metric_alarm.no_recent_success.alarm_name
}

output "start_command" {
  description = "The command to start this stage now, on its own."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.this.arn} --input '{}'"
}
