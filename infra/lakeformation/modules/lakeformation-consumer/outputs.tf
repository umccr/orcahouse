output "resource_link_database_name" {
  description = "Name of the Glue resource link database in the consumer account"
  value       = aws_glue_catalog_database.resource_link.name
}

output "consumer_account_id" {
  description = "Account ID of this consumer"
  value       = var.this_account_id
}

output "granted_principals" {
  description = "List of IAM principals granted access"
  value       = keys(var.principal_grants)
}
