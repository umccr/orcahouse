output "rule_names" {
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
  description = "Map of rule key (e.g. glue-job-failure) to the created EventBridge rule name."
}

output "rule_arns" {
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.arn }
  description = "Map of rule key to the created EventBridge rule ARN."
}
