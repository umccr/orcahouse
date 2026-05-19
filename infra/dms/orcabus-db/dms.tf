# The main DMS resources

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${local.name_prefix}-dms-subnet-group"
  replication_subnet_group_description = "DMS compute subnet group for ${local.name_prefix}"
  subnet_ids                           = data.aws_subnets.uom_private_subnets_ids.ids

  # explicit depends_on "dms_vpc_role"
  depends_on = [aws_iam_role_policy_attachment.dms_vpc_role]
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id    = "${local.name_prefix}-replication-instance"
  replication_instance_class = "dms.t3.medium"
  engine_version             = "3.6.1" # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_ReleaseNotes.html
  allocated_storage          = 20      # GB
  apply_immediately          = true
  auto_minor_version_upgrade = true
  multi_az                   = false
  publicly_accessible        = false

  replication_subnet_group_id = aws_dms_replication_subnet_group.this.id
  vpc_security_group_ids      = [data.aws_security_group.uom_primary_sg.id]
}

resource "aws_dms_endpoint" "source" {
  for_each = toset(local.databases)

  endpoint_id                     = "${local.name_prefix}-source-${replace(each.key, "_", "-")}"
  endpoint_type                   = "source"
  engine_name                     = "aurora-postgresql"
  database_name                   = each.key
  secrets_manager_arn             = data.aws_secretsmanager_secret.source.arn
  secrets_manager_access_role_arn = aws_iam_role.dms_compute.arn
  ssl_mode                        = "require"
}

resource "aws_dms_s3_endpoint" "target" {
  for_each = toset(local.databases)

  endpoint_id   = "${local.name_prefix}-target-s3-${replace(each.key, "_", "-")}"
  endpoint_type = "target"

  service_access_role_arn = aws_iam_role.dms_s3.arn

  bucket_name   = data.aws_s3_bucket.lz.bucket
  bucket_folder = "orcabus/v1/cdc/${each.key}"

  include_op_for_full_load                    = true
  use_task_start_time_for_full_load_timestamp = true

  cdc_inserts_and_updates = true
  cdc_inserts_only        = false
  cdc_max_batch_interval  = 3600   # in seconds, 1 hour
  cdc_min_file_size       = 131072 # set between 128MB (131072) to 512MB (524288)

  data_format                      = "parquet"
  parquet_version                  = "parquet-2-0"
  parquet_timestamp_in_millisecond = true
  compression_type                 = "GZIP"

  # Partition by date
  date_partition_enabled   = true
  date_partition_sequence  = "YYYYMMDD"
  date_partition_delimiter = "SLASH"

  # CDC timestamp column
  timestamp_column_name = "_dms_cdc_timestamp"
}

resource "aws_dms_replication_task" "this" {
  for_each = toset(local.databases)

  replication_task_id      = "${local.name_prefix}-task-${replace(each.key, "_", "-")}"
  replication_instance_arn = aws_dms_replication_instance.this.replication_instance_arn
  migration_type           = "full-load-and-cdc"

  source_endpoint_arn = aws_dms_endpoint.source[each.key].endpoint_arn
  target_endpoint_arn = aws_dms_s3_endpoint.target[each.key].endpoint_arn

  table_mappings = jsonencode({
    rules = [
      {
        rule-type   = "selection"
        rule-id     = "1"
        rule-name   = "include-all-tables"
        rule-action = "include"
        object-locator = {
          schema-name = "public"
          table-name  = "%"
        }
      }
    ]
  })

  # See "Task Settings" at AWS DMS documentation
  # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.html
  replication_task_settings = jsonencode({

    # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.TargetMetadata.html
    TargetMetadata = {
      SupportLobs        = true
      FullLobMode        = false
      LimitedSizeLobMode = true
      LobMaxSize         = 32768 # in KB
    }

    # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.FullLoad.html
    FullLoadSettings = {
      TargetTablePrepMode = "DO_NOTHING"
      MaxFullLoadSubTasks = 8
      CommitRate          = 50000
    }

    # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.Logging.html
    Logging = {
      EnableLogging = true
      LogComponents = [
        { Id = "SOURCE_UNLOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_LOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TASK_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" }
      ]
    }

  })
}
