terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/vpc/warehouse-vpc/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.43.0"
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

variable "umccr_subnet_tier" {
  # Follow UMCCR convention - all lowercase letters
  # https://github.com/umccr/wiki/tree/600dfe6/computing/cloud/amazon#conventions
  default = {
    PRIVATE  = "private"
    PUBLIC   = "public"
    DATABASE = "database"
  }
}

variable "aws_cdk_subnet_type" {
  # Follow CDK convention
  # https://github.com/aws/aws-cdk/blob/v1.44.0/packages/@aws-cdk/aws-ec2/lib/vpc.ts#L139
  default = {
    PRIVATE  = "Private"
    PUBLIC   = "Public"
    ISOLATED = "Isolated"
  }
}

module "warehouse_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "warehouse-vpc"
  cidr = "172.29.0.0/18"

  azs              = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  public_subnets   = ["172.29.0.0/23", "172.29.2.0/23", "172.29.4.0/23"]
  private_subnets  = ["172.29.6.0/23", "172.29.8.0/23", "172.29.10.0/23"]
  database_subnets = ["172.29.12.0/23", "172.29.14.0/23", "172.29.16.0/23"]

  # No NAT Gateway
  enable_nat_gateway = false

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_nat_gateway_route      = false # true to give internet access (egress only)
  create_database_internet_gateway_route = false # true for ingress from internet (NOT RECOMMENDED FOR PRODUCTION)

  enable_dns_hostnames = true
  enable_dns_support   = true

  # No Public IP by default. See https://github.com/umccr/infrastructure/issues/432
  map_public_ip_on_launch = false

  # See README Subnet Tagging section for the following tags combination
  public_subnet_tags = {
    SubnetType            = var.umccr_subnet_tier.PUBLIC
    Tier                  = var.umccr_subnet_tier.PUBLIC
    "aws-cdk:subnet-name" = var.umccr_subnet_tier.PUBLIC
    "aws-cdk:subnet-type" = var.aws_cdk_subnet_type.PUBLIC
  }

  private_subnet_tags = {
    SubnetType            = var.umccr_subnet_tier.PRIVATE
    Tier                  = var.umccr_subnet_tier.PRIVATE
    "aws-cdk:subnet-name" = var.umccr_subnet_tier.PRIVATE
    "aws-cdk:subnet-type" = var.aws_cdk_subnet_type.PRIVATE
  }

  database_subnet_tags = {
    SubnetType            = var.umccr_subnet_tier.DATABASE
    Tier                  = var.umccr_subnet_tier.DATABASE
    "aws-cdk:subnet-name" = var.umccr_subnet_tier.DATABASE
    "aws-cdk:subnet-type" = var.aws_cdk_subnet_type.ISOLATED
  }
}

module "warehouse_vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.6.1"

  vpc_id             = module.warehouse_vpc.vpc_id
  security_group_ids = []

  # See below for config example
  # https://github.com/terraform-aws-modules/terraform-aws-vpc/tree/master/modules/vpc-endpoints
  # https://github.com/terraform-aws-modules/terraform-aws-vpc/tree/master/examples/complete

  endpoints = {

    # Enable Gateway VPC endpoints for S3 and DynamoDB
    # No additional charge for using Gateway Endpoints https://docs.aws.amazon.com/vpc/latest/userguide/vpce-gateway.html

    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.warehouse_vpc.database_route_table_ids, module.warehouse_vpc.private_route_table_ids, module.warehouse_vpc.public_route_table_ids])
      tags            = { Name = "s3-vpc-endpoint" }
    },
    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = flatten([module.warehouse_vpc.database_route_table_ids, module.warehouse_vpc.private_route_table_ids, module.warehouse_vpc.public_route_table_ids])
      # policy          = data.aws_iam_policy_document.dynamodb_endpoint_policy.json
      tags = { Name = "dynamodb-vpc-endpoint" }
    },

    # Note that Interface Endpoints are not free and use AWS PrivateLink https://aws.amazon.com/privatelink/pricing/
    # However it is still more cost effective than NAT Gateway for data communication within AWS Services

    # ecr_api = {
    #   service         = "ecr.api"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "ecr-api-vpc-endpoint" }
    # },
    # ecr_dkr = {
    #   service         = "ecr.dkr"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "ecr-dkr-vpc-endpoint" }
    # },
    # ecs = {
    #   service         = "ecs"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "ecs-vpc-endpoint" }
    # },
    # ecs_agent = {
    #   service         = "ecs-agent"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "ecs-agent-vpc-endpoint" }
    # },
    # ecs_telemetry = {
    #   service         = "ecs-telemetry"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "ecs-telemetry-vpc-endpoint" }
    # },
    # logs = {
    #   service         = "logs"
    #   subnet_ids      = module.warehouse_vpc.private_subnets
    #   tags            = { Name = "logs-vpc-endpoint" }
    # }

  }
}

# ---

# EC2 Instance Connect Endpoint (EICE)
# https://aws.amazon.com/blogs/compute/secure-connectivity-from-public-to-private-introducing-ec2-instance-connect-endpoint-june-13-2023/
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/eice-quotas.html

resource "aws_security_group" "warehouse_vpc_sg_eice" {
  name        = "warehouse-vpc-sg-eice"
  description = "Warehouse VPC Security Group allow traffic through EC2 Instance Connect Endpoint"
  vpc_id      = module.warehouse_vpc.vpc_id

  # Allows SSH traffic within the VPC through this group
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.warehouse_vpc.vpc_cidr_block]
    self        = true
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.warehouse_vpc.vpc_cidr_block]
    self        = true
  }
}

resource "aws_ec2_instance_connect_endpoint" "warehouse_vpc_eice" {
  subnet_id = module.warehouse_vpc.private_subnets[0] # az ap-southeast-2a

  security_group_ids = [
    aws_security_group.warehouse_vpc_sg_eice.id,
  ]
}
