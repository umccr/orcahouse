resource "aws_glue_catalog_database" "this" {
  name = "${var.database_prefix}_${var.environment}_${var.schema}"
}

resource "aws_glue_crawler" "this" {
  name          = "${var.name_prefix}-${var.environment}-${var.schema}-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.this.name

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables     = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
    Grouping = {
      TableGroupingPolicy     = "CombineCompatibleSchemas"
      TableLevelConfiguration = 5 # count inclusive of bucket name towards the table name
    }
  })

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  s3_target {
    path = "s3://${var.bucket_name}/v1/parquet/${var.schema}/"

    exclusions = [
      "**/manifest"
    ]
  }

  # TODO - we could do event-based notification or steps orchestration
  # Runs once a day in UTC - 4:00 AM Sydney time AEDT
  schedule = "cron(0 18 * * ? *)"
}
