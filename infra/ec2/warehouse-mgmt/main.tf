terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/ec2/warehouse-mgmt/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.45.0"
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

# ---

locals {
  stack_name = "orcahouse"
}

data "aws_vpc" "primary" {
  tags = {
    Name = "UomPrimaryVpc"
  }
}

data "aws_subnet" "uom_private_subnets_id_az1" {
  filter {
    name   = "tag:Name"
    values = ["UomPrimaryPrivateSubnetA"] # intentionally fixing it to Zone A, ap-southeast-2a
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

data "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${local.stack_name}-ssm-instance-profile"
}

# ---

resource "aws_instance" "mgmt" {

  # Find AMI with preinstalled SSM agent
  # https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html

  # via Ec2 Console Search Filter > AMI Catalog
  # Ubuntu Server 26.04 LTS (HVM), SSD Volume Type
  # ami-0a59248a6294cece2 (64-bit (x86)) / ami-05eb7cacb94435ecb (64-bit (Arm))
  ami                         = "ami-05eb7cacb94435ecb"
  instance_type               = "t4g.nano"
  hibernation                 = true
  associate_public_ip_address = false
  iam_instance_profile        = data.aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id                   = data.aws_subnet.uom_private_subnets_id_az1.id

  vpc_security_group_ids = [
    data.aws_security_group.uom_primary_sg.id,
  ]

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${local.stack_name}-mgmt-instance"
  }
}

# ---

output "instance_id" {
  value = aws_instance.mgmt.id
}

output "ssm_command" {
  value = "aws ssm start-session --target ${aws_instance.mgmt.id}"
}
