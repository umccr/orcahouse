output "state_machine_arn" {
  description = "The OrcaVault runner state machine."
  value       = aws_sfn_state_machine.run.arn
}

output "start_run_command" {
  description = "The command to start a run now."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.run.arn} --input '{}'"
}

output "results_bucket" {
  description = "The bucket for a run's event which is uploaded to runs/<run_id>/event.json."
  value       = aws_s3_bucket.results.bucket
}

output "manifest_uri" {
  description = "The dbt manifest of the latest run."
  value       = "s3://${aws_s3_bucket.results.bucket}/${local.manifest_key}"
}

output "debug_command" {
  description = "The command to run dbt debug in the task."
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.this.name} \
      --task-definition ${aws_ecs_task_definition.dbt.arn} \
      --launch-type FARGATE \
      --network-configuration 'awsvpcConfiguration={subnets=[${join(",", data.aws_subnets.uom_private_subnets_ids.ids)}],securityGroups=[${data.aws_security_group.uom_primary_sg.id}],assignPublicIp=DISABLED}' \
      --overrides '{"containerOverrides":[{"name":"${local.container_name}","command":["debug","--connection"]}]}'
  EOT
}

output "logs_command" {
  description = "The command to follow the dbt logs."
  value       = "aws logs tail ${aws_cloudwatch_log_group.dbt.name} --follow"
}

output "dbt_task_db_identity" {
  description = "The Redshift database user the dbt task connects as."
  value       = "IAMR:${aws_iam_role.dbt_task.name}"
}
