
################################################################################
# Lambda for Workflow Manager event handling

locals {
  wfm = {
    function_name = "wfm_event_handler"
  }
}

module "wfm_sc" {
  source = "../common/ingest_pipe"

  service_id     = "WFMSC"
  iam_path       = "/orcavault/serviceingestion/wfm_sc/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "WorkflowRunStateChange"
    ],
    source = [
      "orcabus.workflowmanager"
    ]
  }

  lambda_function_name     = local.wfm.function_name
  lambda_function_handler  = "${local.wfm.function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.wfm.function_name}",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.wfm.function_name}.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}
