
################################################################################
# Lambda for Workflow Manager event handling


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

  lambda_function_name     = "wfm_event_handler"
  lambda_function_handler  = "wfm_event_handler.handler"
  lambda_source_paths      = [
    "lambda/wfm_event_handler",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/wfm_event_handler.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}

