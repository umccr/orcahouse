output "publisher_role_arn" {
  value       = aws_iam_role.publisher.arn
  description = "ARN of the EventBridge publisher role for this environment."
}
