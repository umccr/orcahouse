output "cluster_identifier" {
  description = "The RDS cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "The RDS cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "The RDS cluster resource ID (used for rds-db:connect IAM resources)."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "cluster_endpoint" {
  description = "The writer endpoint for the RDS cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "The reader endpoint for the RDS cluster."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "account_id" {
  description = "The AWS account ID of the caller."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region."
  value       = data.aws_region.current.region
}
