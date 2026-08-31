# If the consumer account is having additional roles (anything more than Admin Role) for operational use,
# then we need to configure the LakeFormation permissions on these additional roles.
#
# Login to umccr-prod account and navigate to
# Console > AWS Lake Formation > Data permissions

data "aws_iam_roles" "sso_prod_ops" {
  name_regex  = "AWSReservedSSO_ProdOperator_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "sso_prod_exp" {
  name_regex  = "AWSReservedSSO_ProdDataExplorer_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  consumer_principals = concat(
    tolist(data.aws_iam_roles.sso_prod_ops.arns),
    tolist(data.aws_iam_roles.sso_prod_exp.arns)
  )
}

resource "aws_lakeformation_permissions" "resource_link_database" {
  for_each = {
    for item in flatten([
      for principal in local.consumer_principals : [
        for db_name in keys(module.lakeformation_consumer.resource_link_database_names) : {
          key       = "${principal}__${db_name}"
          principal = principal
          db_name   = db_name
        }
      ]
    ]) : item.key => item
  }

  principal   = each.value.principal
  permissions = ["DESCRIBE"]

  database {
    name       = each.value.db_name
    catalog_id = data.aws_caller_identity.current.account_id
  }

  depends_on = [
    module.lakeformation_consumer
  ]

  # FIXME known provider bug that keep detecting - permissions forces replacement with "ALL"
  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "resource_link_tables" {
  for_each = {
    for item in flatten([
      for principal in local.consumer_principals : [
        for local_db, source_db in module.lakeformation_consumer.resource_link_database_names : {
          key        = "${principal}__${local_db}"
          principal  = principal
          source_db  = source_db
        }
      ]
    ]) : item.key => item
  }

  principal   = each.value.principal
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = each.value.source_db    # ← warehouse database name
    catalog_id    = "115253169271"          # ← warehouse account ID
    wildcard      = true
  }

  depends_on = [
    module.lakeformation_consumer
  ]
}
