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

data "aws_security_group" "primary" {
  provider = aws.unimelb

  vpc_id = data.aws_vpc.primary.id
  tags = {
    Name = "UomPrimaryVpcEndpoints"
  }
}

data "aws_subnets" "uom_private_subnets_ids" {
  provider = aws.unimelb

  filter {
    name   = "tag:Network"
    values = ["Private"]
  }
}

resource "aws_vpc_endpoint" "orcabus_db" {
  provider = aws.unimelb

  vpc_id            = data.aws_vpc.primary.id
  service_name      = aws_vpc_endpoint_service.orcabus_db.service_name
  vpc_endpoint_type = "Interface"

  subnet_ids = data.aws_subnets.uom_private_subnets_ids.ids

  security_group_ids = [
    data.aws_security_group.primary.id
  ]

  private_dns_enabled = false

  tags = {
    Name = "OrcaBusDbEndpoint"
  }
}

# ---

output "vpce_dns_names" {
  value = aws_vpc_endpoint.orcabus_db.dns_entry
}
