# The main Redshift resources

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name        = var.namespace_name
  db_name               = var.db_name
  manage_admin_password = true

  default_iam_role_arn = aws_iam_role.namespace.arn
  iam_roles            = [aws_iam_role.namespace.arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name       = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name       = var.workgroup_name
  base_capacity        = var.base_capacity
  max_capacity         = var.max_capacity
  subnet_ids           = var.subnet_ids
  security_group_ids   = var.security_group_ids
  enhanced_vpc_routing = true
  publicly_accessible  = false

  config_parameter {
    parameter_key   = "auto_mv"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "datestyle"
    parameter_value = "ISO, MDY"
  }
  config_parameter {
    parameter_key   = "enable_case_sensitive_identifier"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "max_query_execution_time"
    parameter_value = "300" # seconds
  }
  config_parameter {
    parameter_key   = "query_group"
    parameter_value = "default"
  }
  config_parameter {
    parameter_key   = "require_ssl"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "search_path"
    parameter_value = "$user, public"
  }
  config_parameter {
    parameter_key   = "use_fips_ssl"
    parameter_value = "true"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_redshiftserverless_usage_limit" "compute_limit" {
  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "serverless-compute"
  amount        = var.compute_limit_amount
  period        = "monthly"
  breach_action = "deactivate"
}

resource "aws_redshiftserverless_usage_limit" "data_limit" {
  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "cross-region-datasharing"
  amount        = var.data_limit_amount
  period        = "monthly"
  breach_action = "deactivate"
}
