
################################################################################
# Lambda for FASTQ Manager event handling

locals {
  fqr = {
    function_name = "fqr_event_handler"
  }
}


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

  lambda_function_name     = local.fqr.function_name
  lambda_function_handler  = "${local.fqr.function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.fqr.function_name}",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.fqr.function_name}.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}

