data "aws_vpc" "main_vpc" {
  tags = var.vpc_tags
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }
  
  tags = {
    Tier = "private"
  }
}

data "aws_iam_policy" "lambda_vpc_access" {
  name = "AWSLambdaVPCAccessExecutionRole"
}

