# The Glue table that Athena queries the run results with. The runner writes the dbt
# run_results.json of each run to v1/run_results/year=<YYYY>/month=<MM>/day=<DD>/<run_id>/run_results.json.
locals {
  run_results_location = "s3://${aws_s3_bucket.results.bucket}/${local.run_results_prefix}"

  # The fields of run_results.json, see https://schemas.getdbt.com/dbt/run-results/v6.json.
  # We can't include all fields in args because there are too many to list, and the parser
  # requires strong types.
  metadata_fields = [
    "dbt_schema_version:string",
    "dbt_version:string",
    "generated_at:string",
    "invocation_id:string",
    "invocation_started_at:string",
    "env:map<string,string>",
  ]

  result_fields = [
    "unique_id:string",
    "status:string",
    "message:string",
    "failures:bigint",
    "execution_time:double",
    "thread_id:string",
    "compiled:boolean",
    "relation_name:string",
    "compiled_code:string",
    "timing:array<struct<name:string,started_at:string,completed_at:string>>",
    "adapter_response:struct<rows_affected:bigint>",
  ]

  args_fields = [
    "which:string",
    "invocation_command:string",
    "full_refresh:boolean",
  ]

  run_results_columns = [
    {
      name    = "metadata"
      type    = "struct<${join(",", local.metadata_fields)}>"
      comment = "The dbt version and invocation. The env has the RUN_ID, ORCAVAULT_REF and ENVIRONMENT."
    },
    {
      name    = "results"
      type    = "array<struct<${join(",", local.result_fields)}>>"
      comment = "A result per node or hook that ran."
    },
    {
      name    = "elapsed_time"
      type    = "double"
      comment = "The seconds the dbt command took."
    },
    {
      name    = "args"
      type    = "struct<${join(",", local.args_fields)}>"
      comment = "The dbt command itself."
    },
  ]
}

resource "aws_glue_catalog_database" "run" {
  name        = local.glue_database_name
  description = "The OrcaVault ${var.environment} run."
}

resource "aws_glue_catalog_table" "run_results" {
  name          = "run_results"
  database_name = aws_glue_catalog_database.run.name
  description   = "The dbt run_results.json for each run."
  table_type    = "EXTERNAL_TABLE"

  # The partitions are projected from the date, so they are never added. Athena reads
  # each one from year=<YYYY>/month=<MM>/day=<DD>/ under the location, which includes
  # each run directory.
  parameters = {
    "EXTERNAL"                      = "TRUE"
    "projection.enabled"            = "true"
    "projection.year.type"          = "date"
    "projection.year.format"        = "yyyy"
    "projection.year.range"         = "2026,NOW"
    "projection.year.interval"      = "1"
    "projection.year.interval.unit" = "YEARS"
    "projection.month.type"         = "integer"
    "projection.month.range"        = "1,12"
    "projection.month.digits"       = "2"
    "projection.day.type"           = "integer"
    "projection.day.range"          = "1,31"
    "projection.day.digits"         = "2"
  }

  partition_keys {
    name    = "year"
    type    = "string"
    comment = "The UTC year the run started."
  }

  partition_keys {
    name    = "month"
    type    = "string"
    comment = "The UTC month the run started."
  }

  partition_keys {
    name    = "day"
    type    = "string"
    comment = "The UTC day the run started."
  }

  storage_descriptor {
    location      = local.run_results_location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hive.hcatalog.data.JsonSerDe"
    }

    dynamic "columns" {
      for_each = local.run_results_columns

      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}
