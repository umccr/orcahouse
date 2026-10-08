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

  # The trust and queue policies pin the warehouse account; refuse any other.
  allowed_account_ids = ["115253169271"]

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
  environment = "dev"
}

variable "slack_topic_arn" {
  description = "ARN of the dev Slack SNS topic the publisher role may publish to."
  type        = string
  default     = "arn:aws:sns:ap-southeast-2:843407916570:AwsChatBotTopic-alerts"
}

variable "disabled_notification_rules" {
  description = "Notification rule keys to deploy DISABLED (maintenance window, OrcaGlue cutover). Example: -var='disabled_notification_rules=[\"glue-job-failure\"]'."
  type        = set(string)
  default     = []
}

# ---

module "publisher_role" {
  source = "../../modules/publisher-role"

  environment     = local.environment
  slack_topic_arn = var.slack_topic_arn
}

output "publisher_role_arn" {
  value       = module.publisher_role.publisher_role_arn
  description = "ARN of the dev EventBridge publisher role."
}

# ---
# Dead-letter queue for every rule target, plus the alarm that fires while it is not empty.
module "target_dlq" {
  source = "../../modules/target-dlq"

  environment = local.environment
}

output "target_dlq_arn" {
  value       = module.target_dlq.target_dlq_arn
  description = "ARN of the dev notification target dead-letter queue."
}

# ---
# EventBridge notification rules on the default bus. DMS CDC and the orcabus-db crawlers
# exist only in prod, so dev passes no DMS ids. Dev watches its own mart crawler, defined
# in infra/glue-crawler/orcavault-db (environments/dev).
module "notification_rules" {
  source = "../../modules/notification-rules"

  environment        = local.environment
  topic_arn          = var.slack_topic_arn
  publisher_role_arn = module.publisher_role.publisher_role_arn
  dlq_arn            = module.target_dlq.target_dlq_arn
  disabled_rules     = var.disabled_notification_rules

  crawler_names = ["orcavault-db-dev-mart-crawler"]
}

output "notification_rule_names" {
  value       = module.notification_rules.rule_names
  description = "Map of rule key to the dev EventBridge notification rule name."
}
