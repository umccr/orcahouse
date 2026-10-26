resource "aws_lakeformation_permissions" "glue_crawler_database" {
  principal = aws_iam_role.glue_crawler.arn

  permissions = ["DESCRIBE", "CREATE_TABLE", "ALTER", "DROP"]

  database {
    name = aws_glue_catalog_database.this.name
  }
}

resource "aws_lakeformation_permissions" "glue_crawler_data_location" {
  principal = aws_iam_role.glue_crawler.arn

  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = "arn:aws:s3:::${var.bucket_name}/v1/parquet/${var.schema}"
  }
}

resource "aws_lakeformation_permissions" "glue_crawler_tables" {
  principal = aws_iam_role.glue_crawler.arn

  permissions = ["SELECT", "DESCRIBE", "ALTER", "INSERT", "DROP", "DELETE"]

  table {
    database_name = aws_glue_catalog_database.this.name
    wildcard      = true
  }
}
