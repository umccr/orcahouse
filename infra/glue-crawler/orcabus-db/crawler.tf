# The main Glue crawler

resource "aws_glue_catalog_database" "this" {
  for_each = toset(local.databases)

  name        = "orcabus_${each.key}"
  description = "Glue catalog database for ${each.key} CDC data"
}

resource "aws_glue_crawler" "this" {
  for_each = toset(local.databases)

  database_name = aws_glue_catalog_database.this[each.key].name
  name          = "${local.name_prefix}-crawler-${replace(each.key, "_", "-")}"
  role          = aws_iam_role.glue_crawler.arn

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns" # Only applies with full_crawl, which adds new columns
      }
    }
    Grouping = {
      TableGroupingPolicy     = "CombineCompatibleSchemas"
      TableLevelConfiguration = 7 # count inclusive of bucket name towards the table name
    }
  })

  # Crawling new folders only forces LOG, so a schema change is only logged, see
  # https://docs.aws.amazon.com/glue/latest/dg/incremental-crawls.html. A full crawl
  # updates the tables, see "Picking up a schema change" in the README.
  schema_change_policy {
    delete_behavior = "LOG" # Log schema deletions — do not drop tables
    update_behavior = var.full_crawl ? "UPDATE_IN_DATABASE" : "LOG"
  }

  lineage_configuration {
    crawler_lineage_settings = "DISABLE"
  }

  recrawl_policy {
    recrawl_behavior = var.full_crawl ? "CRAWL_EVERYTHING" : "CRAWL_NEW_FOLDERS_ONLY" # Only new partitions, unless full_crawl
  }

  s3_target {
    path       = "s3://${data.aws_s3_bucket.lz.bucket}/orcabus/v1/cdc/${each.key}/"
    exclusions = ["*.{tsv,csv,avro,json,orc}"]
  }

  # No schedule. The OrcaVault sources stage starts the crawlers before each run, see
  # infra/orcavault-run.
}
