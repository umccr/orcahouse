# State address moves after refactoring the shared resources into
# ../../modules/aurora. These re-map existing state entries to their new
# module addresses so Terraform updates state instead of destroy/create.
#
# The states have been updated to reflect the new module addresses.
# Safe to delete this file. Keeping it here for historical purposes.

moved {
  from = aws_db_subnet_group.this
  to   = module.aurora.aws_db_subnet_group.this
}

moved {
  from = aws_rds_cluster.this
  to   = module.aurora.aws_rds_cluster.this
}

moved {
  from = aws_rds_cluster_instance.this
  to   = module.aurora.aws_rds_cluster_instance.this
}

moved {
  from = aws_rds_cluster_parameter_group.this
  to   = module.aurora.aws_rds_cluster_parameter_group.this
}

moved {
  from = aws_iam_role.analytics_role
  to   = module.aurora.aws_iam_role.analytics_role
}

moved {
  from = aws_iam_role_policy.analytics_policy
  to   = module.aurora.aws_iam_role_policy.analytics_policy
}

moved {
  from = aws_rds_cluster_role_association.analytics
  to   = module.aurora.aws_rds_cluster_role_association.analytics
}

moved {
  from = aws_iam_role.rds_s3_import_role
  to   = module.aurora.aws_iam_role.rds_s3_import_role
}

moved {
  from = aws_iam_role_policy.rds_s3_policy
  to   = module.aurora.aws_iam_role_policy.rds_s3_policy
}

moved {
  from = aws_rds_cluster_role_association.this
  to   = module.aurora.aws_rds_cluster_role_association.this
}
