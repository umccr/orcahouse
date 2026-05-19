# The main Glue crawler

resource "aws_glue_catalog_database" "this" {
  for_each = toset(local.databases)

  name        = "orcabus_${each.key}"
  description = "Glue catalog database for ${each.key} CDC data"
}

resource "aws_glue_crawler" "this" {
  for_each = toset(local.databases)

  database_name = "orcabus_${each.key}"
  name          = "${local.name_prefix}-crawler-${replace(each.key, "_", "-")}"
  role          = aws_iam_role.glue_crawler.arn

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns" # Add new columns on schema evolution
      }
    }
    Grouping = {
      TableGroupingPolicy     = "CombineCompatibleSchemas"
      TableLevelConfiguration = 7 # folder depth — database/schema/table
    }
  })

  schema_change_policy {
    delete_behavior = "LOG" # Log schema deletions — do not drop tables
    update_behavior = "LOG" # Log update schema changes
  }

  lineage_configuration {
    crawler_lineage_settings = "DISABLE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY" # Only crawl new partitions
  }

  s3_target {
    path       = "s3://${data.aws_s3_bucket.lz.bucket}/orcabus/v1/cdc/${each.key}/"
    exclusions = ["*.{tsv,csv,avro,json,orc}"]
  }

  # Runs at the top of every hour, every day in UTC
  schedule = "cron(0 * * * ? *)"
}
