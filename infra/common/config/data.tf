data "aws_vpc" "main_vpc" {
  tags = var.vpc_tags
}