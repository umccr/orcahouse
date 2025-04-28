
################################################################################
# Lambda for FASTQ Manager event handling


module "fqr_sc" {
  source = "../common/ingest_pipe"

  service_id     = "FQRSC"
  iam_path       = "/orcavault/serviceingestion/fqr_sc/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "FastqListRowStateChange"
    ],
    source = [
      "orcabus.fastqmanager"
    ]
  }

  lambda_function_name     = "fqr_event_handler"
  lambda_function_handler  = "fqr_event_handler.handler"
  lambda_source_paths      = [
    "lambda/fqr_event_handler",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/fqr_event_handler.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}

