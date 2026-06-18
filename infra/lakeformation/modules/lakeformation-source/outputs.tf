output "ram_share_arn" {
  description = "ARN of the RAM resource share"
  value       = aws_ram_resource_share.lakeformation_share.arn
}

output "shared_database_name" {
  description = "The Glue database being shared"
  value       = var.database_name
}

output "data_filter_names" {
  description = "Map of all data cell filters created"
  value = {
    for k, v in aws_lakeformation_data_cells_filter.filters :
    k => v.table_data[0].name
  }
}

output "consumer_account_ids" {
  description = "List of consumer account IDs granted access"
  value       = var.consumer_account_ids
}
