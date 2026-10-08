output "target_dlq_arn" {
  value       = aws_sqs_queue.this.arn
  description = "ARN of the notification target dead-letter queue for this environment."

  # Rule targets consume this ARN; wait for the queue policy so EventBridge can write to
  # the queue as soon as a target uses it.
  depends_on = [aws_sqs_queue_policy.this]
}

output "dlq_alarm_name" {
  value       = aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name
  description = "Name of the CloudWatch alarm that fires while the DLQ holds undelivered alerts."
}
