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

data "aws_rds_cluster" "orcabus_db" {
  provider = aws.umccr

  cluster_identifier = "orcabus-db"
}

data "aws_security_group" "orcabus_compute_sg" {
  provider = aws.umccr

  id = "sg-02e363a39220c955f" # OrcaBusSharedComputeSecurityGroup
}

# ---

resource "aws_security_group_rule" "allow_uom_cidr" {
  provider = aws.umccr

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.primary.cidr_block]
  security_group_id = data.aws_security_group.orcabus_compute_sg.id
  description       = "Allow connection from Data Warehouse account VPC"
}

resource "aws_lb" "nlb" {
  provider = aws.umccr

  name               = "orcabus-db-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = data.aws_subnets.database_subnets_ids.ids
  security_groups    = [data.aws_security_group.orcabus_compute_sg.id]
}

resource "aws_lb_target_group" "tg" {
  provider = aws.umccr

  name        = "orcabus-db-tg"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.main_vpc.id
  target_type = "ip" # Target type IP is required for RDS endpoints
}

resource "aws_lb_listener" "listener" {
  provider = aws.umccr

  load_balancer_arn = aws_lb.nlb.arn
  port              = 5432
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Target Group Attachment (Using cluster endpoint IP)
# Requires data source to resolve endpoint to IP if not using proxy
# FIXME - Note on IP Stability for NLB.
#  This happens only one-off apply at deploy time.
#  Because Aurora endpoints are DNS-based and the underlying IPs can change during scaling or failover,
#  need a side-car Lambda-based updater to keep the Target Group IPs in sync with the Aurora endpoint.
#  Refer to the AWS blog post article mentioned in the README.
data "dns_a_record_set" "rds_endpoint" {
  host = data.aws_rds_cluster.orcabus_db.endpoint
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  provider = aws.umccr

  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = data.dns_a_record_set.rds_endpoint.addrs[0]
  port             = 5432
}

resource "aws_vpc_endpoint_service" "orcabus_db" {
  provider = aws.umccr

  acceptance_required        = false
  allowed_principals         = ["arn:aws:iam::115253169271:root"]
  supported_regions          = ["ap-southeast-2"]
  network_load_balancer_arns = [aws_lb.nlb.arn]

  tags = {
    Name = "orcabus-db-endpoint-service"
  }
}

# ---

output "endpoint_service_name" {
  value = aws_vpc_endpoint_service.orcabus_db.service_name
}

output "rds_addresses" {
  value = data.dns_a_record_set.rds_endpoint.addrs
}

output "rds_target_ip" {
  value = aws_lb_target_group_attachment.tg_attach.target_id
}
