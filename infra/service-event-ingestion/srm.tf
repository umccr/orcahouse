################################################################################
# Lambda for Sequence Run Manager event handling

# Sequence Run State Change
module "srm_sc" {
  source = "../common/ingest_pipe"

  service_id     = "SRMSC"
  iam_path       = "/orcavault/serviceingestion/srm_sc/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "SequenceRunStateChange"
    ],
    source = [
      "orcabus.sequencerunmanager"
    ]
  }

  lambda_function_name     = "srm_sc_event_handler"
  lambda_function_handler  = "srm_sc_event_handler.handler"
  lambda_source_paths      = [
    "lambda/srm_sc_event_handler",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/srm_sc_event_handler.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}


# Sequence Run Library Linking Change
module "srm_llc" {
  source = "../common/ingest_pipe"

  service_id = "SRMLLC"
  iam_path = "/orcavault/serviceingestion/srm_llc/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "SequenceRunLibraryLinkingChange"
    ],
    source = [
      "orcabus.sequencerunmanager"
    ]
  }

  lambda_function_name = "srm_llc_event_handler"
  lambda_function_handler = "srm_llc_event_handler.handler"
  lambda_source_paths = [ 
    "lambda/srm_llc_event_handler",
    "lambda/utils/utils.py" 
    ]
  lambda_artefact_out_path = ".temp/lambda/srm_llc_event_handler.zip"
  lambda_layers = [aws_lambda_layer_version.psycopg2_layer.arn]
}

