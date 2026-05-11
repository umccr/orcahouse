terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/vpc/peer-main-vpc/terraform.tfstate"
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
  alias = "main"

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

provider "aws" {
  alias = "peer"

  region  = "ap-southeast-2"
  profile = "unimelb-warehouse-prod-owner"

  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

data "aws_vpc" "main" {
  provider = aws.main
  tags = {
    Name = "main-vpc"
  }
}

data "aws_vpc" "peer" {
  provider = aws.peer
  tags = {
    Name = "warehouse-vpc"
  }
}

data "aws_caller_identity" "peer" {
  provider = aws.peer
}

# Requester's side of the connection.
resource "aws_vpc_peering_connection" "main" {
  provider = aws.main

  vpc_id        = data.aws_vpc.main.id
  peer_vpc_id   = data.aws_vpc.peer.id
  peer_owner_id = data.aws_caller_identity.peer.account_id
  auto_accept   = false

  tags = {
    Side = "Requester"
  }
}

# Acceptor's side of the connection.
resource "aws_vpc_peering_connection_accepter" "peer" {
  provider = aws.peer

  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
  auto_accept               = true

  tags = {
    Side = "Accepter"
  }
}

resource "aws_vpc_peering_connection_options" "requester" {
  provider = aws.main

  # As options can't be set until the connection has been accepted
  # create an explicit dependency on the accepter.
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_vpc_peering_connection_options" "accepter" {
  provider = aws.peer

  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.peer.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}
