
################################################################################
# Lambda for Workflow Manager event handling


module "wfr_sc" {
  source = "../common/ingest_pipe"

  service_id     = "WFRSC"
  iam_path       = "/orcavault/serviceingestion/wfr_sc/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "WorkflowRunStateChange"
    ],
    source = [
      "orcabus.workflowmanager"
    ]
  }

  lambda_function_name     = "wfr_event_handler"
  lambda_function_handler  = "wfr_event_handler.handler"
  lambda_source_paths      = [
    "lambda/wfr_event_handler",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/wfr_event_handler.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}

