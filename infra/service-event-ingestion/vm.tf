
################################################################################
# Lambda for Variant Monitoring event handling

locals {
  vm = {
    function_name = "vm_event_handler"
  }
}

module "vm_result" {
  source = "../common/ingest_pipe"

  service_id     = "VMRES"
  iam_path       = "/orcavault/serviceingestion/vm_result/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = [
      "VariantMonitoringResult"
    ],
    source = [
      "orcabus.variantmonitoring"
    ]
  }

  lambda_function_name     = local.vm.function_name
  lambda_function_handler  = "${local.vm.function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.vm.function_name}",
    "lambda/utils/utils.py"
    ]
  lambda_artefact_out_path = ".temp/lambda/${local.vm.function_name}.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}
