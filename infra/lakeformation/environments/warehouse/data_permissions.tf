# The following TF resources configure Lake Formation permissions.
#
# Login to Warehouse account and navigate to
# Console > AWS Lake Formation > Data permissions

# Dynamically list all Glue databases using an external bash command
# data "external" "glue_databases" {
#   program = ["bash", "-c", <<EOT
#     databases=$(aws glue get-databases --query "DatabaseList[].Name" --output json 2>/dev/null || echo "[]")
#     echo "{\"list\": $databases}"
#   EOT
#   ]
# }

locals {

  # The databases are output of the CLI command. We can use external resource to wire this.
  #   aws glue get-databases --query "DatabaseList[].Name" --output json 2>/dev/null || echo "[]"
  databases = [
    "data_portal",
    "default",
    "oncovault_dev_dcl",
    "oncovault_dev_mart",
    "orcabus_filemanager",
    "orcabus_metadata_manager",
    "orcabus_sequence_run_manager",
    "orcabus_workflow_manager",
    "tidywigits"
  ]

  # Account ID helper
  account_id = data.aws_caller_identity.current.account_id
}

# ==========================================
# 1. PERMISSIONS FOR DBT (PowerUserAccess)
# ==========================================
resource "aws_lakeformation_permissions" "dbt_database" {
  for_each  = toset(local.databases)
  principal = tolist(data.aws_iam_roles.warehouse_sso_power_user.arns)[0]

  database {
    name = each.value
  }
  permissions = ["DESCRIBE", "CREATE_TABLE", "ALTER", "DROP"]
}

resource "aws_lakeformation_permissions" "dbt_tables" {
  for_each  = toset(local.databases)
  principal = tolist(data.aws_iam_roles.warehouse_sso_power_user.arns)[0]

  table {
    database_name = each.value
    wildcard      = true # <-- Magic wildcard! Covers 100s of tables in 1 rule.
  }
  permissions = ["SELECT", "INSERT", "ALTER", "DROP", "DELETE"]
}

# ==========================================
# 2. PERMISSIONS FOR GLUE CRAWLER
# ==========================================
resource "aws_lakeformation_permissions" "crawler_database" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.crawler.arn

  database {
    name = each.value
  }
  permissions = ["DESCRIBE", "CREATE_TABLE"]
}

resource "aws_lakeformation_permissions" "crawler_tables" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.crawler.arn

  table {
    database_name = each.value
    wildcard      = true
  }
  permissions = ["SELECT", "ALTER", "DROP"]
}

# ==========================================
# 3. PERMISSIONS FOR ADMINISTRATORS
# ==========================================
resource "aws_lakeformation_permissions" "admin_database" {
  for_each  = toset(local.databases)
  principal = tolist(data.aws_iam_roles.warehouse_sso_admin.arns)[0]

  database {
    name = each.value
  }
  permissions = ["ALL"]
}

resource "aws_lakeformation_permissions" "admin_tables" {
  for_each  = toset(local.databases)
  principal = tolist(data.aws_iam_roles.warehouse_sso_admin.arns)[0]

  table {
    database_name = each.value
    wildcard      = true
  }
  permissions = ["ALL"]
}

# ==========================================
# 4. PERMISSIONS FOR Redshift - dev
# ==========================================
resource "aws_lakeformation_permissions" "redshift_dev_database" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.redshift_dev.arn

  database {
    name = each.value
  }
  permissions = ["DESCRIBE"]
}

resource "aws_lakeformation_permissions" "redshift_dev_tables" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.redshift_dev.arn

  table {
    database_name = each.value
    wildcard      = true # Natively covers all tables
  }
  permissions = ["SELECT", "DESCRIBE"]
}

# ==========================================
# 5. PERMISSIONS FOR Redshift - prod
# ==========================================
resource "aws_lakeformation_permissions" "redshift_prod_database" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.redshift_prod.arn

  database {
    name = each.value
  }
  permissions = ["DESCRIBE"]
}

resource "aws_lakeformation_permissions" "redshift_prod_tables" {
  for_each  = toset(local.databases)
  principal = data.aws_iam_role.redshift_prod.arn

  table {
    database_name = each.value
    wildcard      = true # Natively covers all tables
  }
  permissions = ["SELECT", "DESCRIBE"]
}
