locals {
  database_name = "orcavault"
}

data "aws_ssm_parameter" "orcavault_tsa_username" {
  name = "/${local.stack_name}/${local.database_name}/tsa_username"
}

data "aws_secretsmanager_secret" "orcavault_tsa" {
  name = "${local.stack_name}/${local.database_name}/${data.aws_ssm_parameter.orcavault_tsa_username.value}"
}

# ---

resource "aws_glue_connection" "orcavault_tsa" {
  name = "${local.stack_name}-${local.database_name}-${data.aws_ssm_parameter.orcavault_tsa_username.value}"

  # https://docs.aws.amazon.com/glue/latest/dg/connection-properties.html
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:postgresql://${data.aws_rds_cluster.orcahouse_db.endpoint}:5432/${local.database_name}"
    SECRET_ID           = data.aws_secretsmanager_secret.orcavault_tsa.name
  }

  physical_connection_requirements {
    security_group_id_list = sort([var.orcabus_compute_sg_id.prod])
    subnet_id              = data.aws_subnet.selected.id
    availability_zone      = data.aws_subnet.selected.availability_zone
  }
}

# ---

resource "aws_s3_object" "requirements_txt" {
  bucket = data.aws_s3_bucket.glue_script_bucket.bucket
  key    = "glue/requirements.txt"
  source = "../requirements.txt"
  etag   = filemd5("../requirements.txt")
}

# ---

resource "aws_s3_object" "spreadsheet_library_tracking_metadata" {
  bucket = data.aws_s3_bucket.glue_script_bucket.bucket
  key    = "glue/spreadsheet_library_tracking_metadata/spreadsheet_library_tracking_metadata.py"
  source = "../workspace/spreadsheet_library_tracking_metadata/spreadsheet_library_tracking_metadata.py"
  etag   = filemd5("../workspace/spreadsheet_library_tracking_metadata/spreadsheet_library_tracking_metadata.py")
}

resource "aws_glue_job" "spreadsheet_library_tracking_metadata" {
  name              = "${local.stack_name}-spreadsheet-library-tracking-metadata-job"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  connections = sort([
    aws_glue_connection.orcavault_tsa.name
  ])

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.glue_script_bucket.bucket}/${aws_s3_object.spreadsheet_library_tracking_metadata.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"
    "--python-modules-installer-option" = "-r"
    "--additional-python-modules" = "s3://${data.aws_s3_bucket.glue_script_bucket.bucket}/${aws_s3_object.requirements_txt.key}"
  }
}

resource "aws_glue_trigger" "spreadsheet_library_tracking_metadata" {
  name              = "${aws_glue_job.spreadsheet_library_tracking_metadata.name}-scheduled-trigger"
  type              = "SCHEDULED"
  schedule          = "cron(10 13 * * ? *)"  # Cron expression to run daily at 13:10 PM UTC = AEST/AEDT 00:10 AM
  description       = "Daily trigger for ${aws_glue_job.spreadsheet_library_tracking_metadata.name}"
  start_on_creation = true

  actions {
    job_name = aws_glue_job.spreadsheet_library_tracking_metadata.name
  }

  depends_on = [aws_glue_job.spreadsheet_library_tracking_metadata]
}

# ---

resource "aws_s3_object" "spreadsheet_google_lims" {
  bucket = data.aws_s3_bucket.glue_script_bucket.bucket
  key    = "glue/spreadsheet_google_lims/spreadsheet_google_lims.py"
  source = "../workspace/spreadsheet_google_lims/spreadsheet_google_lims.py"
  etag   = filemd5("../workspace/spreadsheet_google_lims/spreadsheet_google_lims.py")
}

resource "aws_glue_job" "spreadsheet_google_lims" {
  name              = "${local.stack_name}-spreadsheet-google-lims-job"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  connections = sort([
    aws_glue_connection.orcavault_tsa.name
  ])

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.glue_script_bucket.bucket}/${aws_s3_object.spreadsheet_google_lims.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"
    "--python-modules-installer-option" = "-r"
    "--additional-python-modules" = "s3://${data.aws_s3_bucket.glue_script_bucket.bucket}/${aws_s3_object.requirements_txt.key}"
  }
}

resource "aws_glue_trigger" "spreadsheet_google_lims" {
  name              = "${aws_glue_job.spreadsheet_google_lims.name}-scheduled-trigger"
  type              = "SCHEDULED"
  schedule          = "cron(10 13 * * ? *)"  # Cron expression to run daily at 13:10 PM UTC = AEST/AEDT 00:10 AM
  description       = "Daily trigger for ${aws_glue_job.spreadsheet_google_lims.name}"
  start_on_creation = true

  actions {
    job_name = aws_glue_job.spreadsheet_google_lims.name
  }

  depends_on = [aws_glue_job.spreadsheet_google_lims]
}
