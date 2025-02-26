terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-aurora/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.78.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

locals {
  stack_name = "orcahouse"
}

data "aws_ssm_parameter" "master_username" {
  name = "/${local.stack_name}/master_username"
}

data "aws_vpc" "main_vpc" {
  # Using tags filter on networking stack to get main-vpc
  tags = {
    Name        = "main-vpc"
    Stack       = "networking"
    Environment = terraform.workspace
  }
}

data "aws_subnets" "database_subnets_ids" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "database"
  }
}

variable "portal_compute_sg_id" {
  default = {
    dev  = ""
    prod = "sg-01a1e6678bc643a56"
    stg  = ""
  }
}

variable "orcabus_compute_sg_id" {
  default = {
    dev  = ""
    prod = "sg-02e363a39220c955f"
    stg  = ""
  }
}

resource "aws_security_group" "this" {
  vpc_id      = data.aws_vpc.main_vpc.id
  name        = "${local.stack_name}-db-sg"
  description = "Allow inbound traffic within the group"

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.stack_name}-db-subnet-group"
  subnet_ids = data.aws_subnets.database_subnets_ids.ids
}

resource "aws_rds_cluster" "this" {
  cluster_identifier          = "orcahouse-db"
  engine                      = "aurora-postgresql"
  engine_mode                 = "provisioned"
  engine_version              = "16.4"
  master_username             = data.aws_ssm_parameter.master_username.value
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  backup_retention_period     = 7
  deletion_protection         = true
  storage_encrypted           = true
  enable_http_endpoint        = true

  vpc_security_group_ids = [
    aws_security_group.this.id,
    var.orcabus_compute_sg_id[terraform.workspace],
    var.portal_compute_sg_id[terraform.workspace]
  ]

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 16.0
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
