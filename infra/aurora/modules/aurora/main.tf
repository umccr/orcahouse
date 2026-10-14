data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "master_username" {
  name = "/${var.stack_name}/master_username"
}

data "aws_vpc" "primary" {
  tags = {
    Name = "UomPrimaryVpc"
  }
}

data "aws_subnets" "uom_private_subnets_ids" {
  filter {
    name   = "tag:Network"
    values = ["Private"]
  }
}

data "aws_security_group" "uom_primary_sg" {
  filter {
    name   = "tag:Name"
    values = ["UomPrimaryVpcEndpoints"]
  }
}

# ---

resource "aws_db_subnet_group" "this" {
  name       = "${var.stack_name}-${var.environment}-db-subnet-group"
  subnet_ids = data.aws_subnets.uom_private_subnets_ids.ids
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = "${var.stack_name}-${var.environment}"
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = var.engine_version
  allow_major_version_upgrade         = false
  master_username                     = data.aws_ssm_parameter.master_username.value
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  backup_retention_period             = var.backup_retention_period
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  storage_encrypted                   = true
  enable_http_endpoint                = true
  skip_final_snapshot                 = var.skip_final_snapshot
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name

  enabled_cloudwatch_logs_exports = [
    "iam-db-auth-error",
    "instance",
    "postgresql",
  ]

  vpc_security_group_ids = [
    data.aws_security_group.uom_primary_sg.id
  ]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }
}

resource "aws_rds_cluster_instance" "this" {
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_rds_cluster.this.db_subnet_group_name
  publicly_accessible  = false
}

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.environment}-${var.stack_name}-aurora-postgresql18-"
  family      = "aurora-postgresql18"
  description = "Custom RDS cluster parameter group for Aurora Postgres 18"

  parameter {
    name         = "aurora_analytics.enabled"
    value        = "1"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}
