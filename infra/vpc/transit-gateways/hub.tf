provider "aws" {
  alias = "umccr"

  region  = "ap-southeast-2"
  profile = "umccr-prod-admin"

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

data "aws_vpc" "main_vpc" {
  provider = aws.umccr

  tags = {
    Name = "main-vpc"
  }
}

data "aws_subnets" "database_subnets_ids" {
  provider = aws.umccr

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "database"
  }
}

data "aws_route_tables" "umccr_private_route_table_ids" {
  provider = aws.umccr

  vpc_id = data.aws_vpc.main_vpc.id

  filter {
    name   = "tag:Name"
    values = ["main-vpc-db"]
  }
}

module "tgw_hub" {
  source = "terraform-aws-modules/transit-gateway/aws"

  providers = {
    aws = aws.umccr
  }

  name        = "OrcaHouseTransitGateway"
  description = "OrcaHouse transit gateway Hub shared with other AWS accounts"

  # When "true" there is no need for RAM resources if using multiple AWS accounts
  enable_auto_accept_shared_attachments = true

  vpc_attachments = {
    vpc1 = {
      vpc_id       = data.aws_vpc.main_vpc.id
      subnet_ids   = data.aws_subnets.database_subnets_ids.ids
      dns_support  = true
      ipv6_support = false

      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false

      tgw_routes = [
        {
          destination_cidr_block = "10.2.0.0/16"
        },
        # {
        #   blackhole              = true
        #   destination_cidr_block = "0.0.0.0/0"
        # }
      ]
    },
  }

  ram_allow_external_principals = true
  ram_principals                = [115253169271]
}
