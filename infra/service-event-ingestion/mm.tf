################################################################################
# Lambda for Metadata Manager event handling

locals {
  mm = {
    lib_function_name  = "mm_lib_event_handler"
  }
}

# Metadata State Change (library)
module "mm_lib" {
  source = "../common/ingest_pipe"

  service_id     = "MMLIB"
  iam_path       = "/orcavault/serviceingestion/mm_lib/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "MetadataStateChange"
    ],
    source = [
      "orcabus.metadatamanager"
    ]
  }

  lambda_function_name     = local.mm.lib_function_name
  lambda_function_handler  = "${local.mm.lib_function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.mm.lib_function_name}",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.mm.lib_function_name}.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}
