output "ecr_repository_url" {
  description = "Push the dbt image here, tagged with orcavault_release_ref."
  value       = aws_ecr_repository.dbt.repository_url
}

output "state_machine_arn" {
  description = "The OrcaVault run state machine."
  value       = aws_sfn_state_machine.run.arn
}

output "start_run_command" {
  description = "Start a full run now. See the README for other requests."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.run.arn} --input '{}'"
}

output "results_bucket" {
  description = "Each run's event, at runs/<execution name>/event.json."
  value       = aws_s3_bucket.results.bucket
}

output "debug_command" {
  description = "Run dbt debug in the task, to check it can reach Redshift."
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.this.name} \
      --task-definition ${aws_ecs_task_definition.dbt.arn} \
      --launch-type FARGATE \
      --network-configuration 'awsvpcConfiguration={subnets=[${join(",", data.aws_subnets.uom_private_subnets_ids.ids)}],securityGroups=[${data.aws_security_group.uom_primary_sg.id}],assignPublicIp=DISABLED}' \
      --overrides '{"containerOverrides":[{"name":"${local.container_name}","command":["debug"]}]}'
  EOT
}

output "logs_command" {
  description = "Follow the dbt logs."
  value       = "aws logs tail ${aws_cloudwatch_log_group.dbt.name} --follow"
}

output "dbt_task_db_identity" {
  description = "Redshift database user the dbt task connects as. See the README for its grants."
  value       = "IAMR:${aws_iam_role.dbt_task.name}"
}

output "alerts_topic_arn" {
  description = "SNS topic receiving run alerts. Subscribe to it after applying."
  value       = aws_sns_topic.alerts.arn
}
