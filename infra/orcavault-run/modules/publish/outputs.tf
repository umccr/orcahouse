output "state_machine_arn" {
  description = "The OrcaVault publish state machine."
  value       = aws_sfn_state_machine.publish.arn
}

output "start_command" {
  description = "The command to publish now, without starting anything after it."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.publish.arn} --input '{}'"
}

output "event" {
  description = "The event every execution sends, for anything that starts after it."
  value = {
    source             = local.event_source
    detail_type        = local.event_detail_type
    outcomes           = local.outcomes
    succeeded_outcomes = local.succeeded_outcomes
  }
}
