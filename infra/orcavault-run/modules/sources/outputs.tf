output "state_machine_arn" {
  description = "The OrcaVault sources state machine."
  value       = aws_sfn_state_machine.sources.arn
}

output "start_command" {
  description = "The command to load the sources now, without starting the run afterwards."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.sources.arn} --input '{}'"
}

output "event" {
  description = "The event every execution sends, for the stage that starts after it."
  value = {
    source             = local.event_source
    detail_type        = local.event_detail_type
    outcomes           = local.outcomes
    succeeded_outcomes = local.succeeded_outcomes
  }
}
