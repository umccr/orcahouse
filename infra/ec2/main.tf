terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-ec2/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
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

module "config" {
  source = "../common/config"
}

# ---

variable "orcabus_compute_sg_id" {
  default = {
    default = "sg-mock-for-testing"
    dev     = "sg-03abb47eba799e044"
    prod    = "sg-02e363a39220c955f"
    stg     = "sg-069849c9157d4fb66"
  }
}

variable "private_subnet_id" {
  # az ap-southeast-2a
  default = {
    default = "subnet-mock-for-testing"
    dev     = "subnet-050e6fb0f6028178b"
    prod    = "subnet-01be4c1109eca3446"
    stg     = "subnet-01308be8bb704e5ef"
  }
}

# ---

data "aws_vpc" "main_vpc" {
  tags = {
    Name        = "main-vpc"
    Stack       = "networking"
    Environment = terraform.workspace
  }
}

data "aws_security_group" "main_vpc_sg_outbound" {
  vpc_id = data.aws_vpc.main_vpc.id

  # allow outbound only traffic
  tags = {
    Name = "outbound_only"
  }
}

data "aws_security_group" "main_vpc_sg_ssh_from_eice" {
  vpc_id = data.aws_vpc.main_vpc.id

  # allow EC2 Instance Connect Endpoint (eice)
  tags = {
    Name = "ssh_from_eice"
  }
}

# ---

resource "aws_iam_role" "ssm_instance_role" {
  name = "${local.stack_name}-ssm-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_instance_policy" {
  role       = aws_iam_role.ssm_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${local.stack_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_instance_role.name
}

resource "aws_instance" "mgmt" {

  # Find AMI with preinstalled SSM agent
  # https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html

  # via Ec2 Console Search Filter > AMI Catalog
  # Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
  # ami-0ba8d27d35e9915fb (64-bit (x86)) / ami-0f05d48c0353e144c (64-bit (Arm))
  ami                         = "ami-0f05d48c0353e144c"
  instance_type               = "t4g.nano"
  hibernation                 = true
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name
  subnet_id                   = var.private_subnet_id[terraform.workspace]

  vpc_security_group_ids = [
    data.aws_security_group.main_vpc_sg_ssh_from_eice.id,
    data.aws_security_group.main_vpc_sg_outbound.id,
    module.config.orcahouse_db_sg_id[terraform.workspace],
    var.orcabus_compute_sg_id[terraform.workspace],
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
