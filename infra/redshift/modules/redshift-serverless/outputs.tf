output "namespace_id" {
  value = aws_redshiftserverless_namespace.this.id
}

output "admin_password_secret_arn" {
  value = aws_redshiftserverless_namespace.this.admin_password_secret_arn
}

output "workgroup_endpoint" {
  value = aws_redshiftserverless_workgroup.this.endpoint
}

output "workgroup_name" {
  value = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "namespace_iam_role_arn" {
  value       = aws_iam_role.namespace.arn
  description = "IAM role ARN attached to the namespace — used for Glue and S3 access"
}
