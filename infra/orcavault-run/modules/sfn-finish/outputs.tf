output "states" {
  description = "The states to merge into the stage's definition."
  value       = local.states
}

output "start_at" {
  description = "The state that a stage goes to once it has assigned $detail."
  value       = "AddRunFields"
}
