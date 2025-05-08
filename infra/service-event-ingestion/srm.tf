################################################################################
# Lambda for Sequence Run Manager event handling

locals {
  srm = {
    sc_function_name  = "srm_sc_event_handler"
    llc_function_name = "srm_llc_event_handler"
  }
}

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

  lambda_function_name     = local.srm.sc_function_name
  lambda_function_handler  = "${local.srm.sc_function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.srm.sc_function_name}",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.srm.sc_function_name}.zip"
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

  lambda_function_name = local.srm.llc_function_name
  lambda_function_handler = "${local.srm.llc_function_name}.handler"
  lambda_source_paths = [ 
    "lambda/${local.srm.llc_function_name}",
    "lambda/utils/utils.py" 
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.srm.llc_function_name}.zip"
  lambda_layers = [aws_lambda_layer_version.psycopg2_layer.arn]
}

