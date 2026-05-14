provider "aws" {
  alias = "unimelb"

  region  = "ap-southeast-2"
  profile = "unimelb-warehouse-prod-admin"

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

data "aws_vpc" "primary" {
  provider = aws.unimelb

  tags = {
    Name = "UomPrimaryVpc"
  }
}

data "aws_subnets" "uom_private_subnets_ids" {
  provider = aws.unimelb

  filter {
    name   = "tag:Network"
    values = ["Private"]
  }
}

data "aws_route_tables" "uom_private_route_table_ids" {
  provider = aws.unimelb

  vpc_id = data.aws_vpc.primary.id

  filter {
    name   = "tag:Network"
    values = ["Private"]
  }
}

module "tgw_peer1" {
  source = "terraform-aws-modules/transit-gateway/aws"

  providers = {
    aws = aws.unimelb
  }

  name        = "OrcaHouseTransitGateway"
  description = "OrcaHouse transit gateway Hub shared with other AWS accounts"

  create_tgw             = false
  share_tgw              = true
  ram_resource_share_arn = module.tgw_hub.ram_resource_share_id

  # When "true" there is no need for RAM resources if using multiple AWS accounts
  enable_auto_accept_shared_attachments = true

  vpc_attachments = {
    vpc2 = {
      tgw_id       = module.tgw_hub.ec2_transit_gateway_id
      vpc_id       = data.aws_vpc.primary.id
      subnet_ids   = data.aws_subnets.uom_private_subnets_ids.ids
      dns_support  = true
      ipv6_support = false

      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false

      # vpc_route_table_ids  = data.aws_route_tables.uom_private_route_table_ids.ids
      # tgw_destination_cidr = "0.0.0.0/0"

      tgw_routes = [
        {
          destination_cidr_block = "10.198.176.0/20"
        },
        # {
        #   blackhole              = true
        #   destination_cidr_block = "0.0.0.0/0"
        # }
      ]
    },
  }
}
