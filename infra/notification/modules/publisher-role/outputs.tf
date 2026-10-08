output "publisher_role_arn" {
  value       = aws_iam_role.publisher.arn
  description = "ARN of the EventBridge publisher role for this environment."

  # Rule targets consume this ARN; wait for the sns:Publish policy so no target goes live
  # before the role can actually publish.
  depends_on = [aws_iam_role_policy.publish]
}
