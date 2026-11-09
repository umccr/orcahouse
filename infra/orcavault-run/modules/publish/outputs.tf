output "state_machine_arn" {
  description = "The OrcaVault publish state machine."
  value       = module.stage.state_machine_arn
}

output "start_command" {
  description = "The command to publish now, without starting anything after it."
  value       = module.stage.start_command
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
