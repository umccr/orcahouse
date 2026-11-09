output "items" {
  description = "The crawler names, for the Map's Items."
  value       = var.crawler_names
}

output "item_processor" {
  description = "The Map's ItemProcessor."
  value       = local.item_processor
}

output "policy_json" {
  description = "The policy the stage's role needs to crawl, for its source_policy_documents. Null without crawlers."
  value       = one(data.aws_iam_policy_document.crawl[*].json)
}
