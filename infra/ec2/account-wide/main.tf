terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/ec2/account-wide/terraform.tfstate"
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

data "aws_subnet" "uom_private_subnets_id_az1" {
  filter {
    name   = "tag:Name"
    values = ["UomPrimaryPrivateSubnetA"] # intentionally fixing it to  Zone A, ap-southeast-2a
  }
}

data "aws_security_group" "uom_primary_sg" {
  filter {
    name   = "tag:Name"
    values = ["UomPrimaryVpcEndpoints"]
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

# EC2 Instance Connect Endpoint (EICE)
# https://aws.amazon.com/blogs/compute/secure-connectivity-from-public-to-private-introducing-ec2-instance-connect-endpoint-june-13-2023/
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/eice-quotas.html
resource "aws_ec2_instance_connect_endpoint" "main_vpc_eice" {
  subnet_id = data.aws_subnet.uom_private_subnets_id_az1.id

  security_group_ids = [
    data.aws_security_group.uom_primary_sg.id,
  ]

  tags = {
    Name = "${local.stack_name}-eice"
  }
}

resource "aws_security_group_rule" "allow_ssh_within_sg" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  self              = true
  security_group_id = data.aws_security_group.uom_primary_sg.id
  description       = "Allow SSH connection within the same security group"
}
