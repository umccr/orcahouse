output "state_machine_arn" {
  description = "The OrcaVault sources state machine."
  value       = module.stage.state_machine_arn
}

output "start_command" {
  description = "The command to load the sources now, without starting the run afterwards."
  value       = module.stage.start_command
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
