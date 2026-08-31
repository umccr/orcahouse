output "resource_link_database_names" {
  description = "Map of local database name to source database name in warehouse account"
  value       = { for k, v in aws_glue_catalog_database.resource_links : k => v.target_database[0].database_name }
}
