terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/notification/dev/terraform.tfstate"
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

locals {
  namespace   = "orcahouse"
  environment = "dev"
}

variable "slack_topic_arn" {
  description = "ARN of the dev Slack SNS topic the publisher role may publish to."
  type        = string
  default     = "arn:aws:sns:ap-southeast-2:843407916570:AwsChatBotTopic-alerts"
}

# ---

# CI does not cover this stack. Before merging, run locally from this dir:
#   terraform init -backend=false && terraform validate
# and from the stack root: terraform fmt -check -recursive ../..

module "publisher_role" {
  source = "../../modules/publisher-role"

  environment     = local.environment
  slack_topic_arn = var.slack_topic_arn
}

output "publisher_role_arn" {
  value       = module.publisher_role.publisher_role_arn
  description = "ARN of the dev EventBridge publisher role."
}
