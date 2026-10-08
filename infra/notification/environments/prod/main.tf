terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/notification/prod/terraform.tfstate"
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
  environment = "prod"
}

variable "slack_topic_arn" {
  description = "ARN of the prod Slack SNS topic the publisher role may publish to."
  type        = string
  default     = "arn:aws:sns:ap-southeast-2:472057503814:AwsChatBotTopic-alerts"
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
  description = "ARN of the prod EventBridge publisher role."
}

# ---
# Dead-letter queue for every rule target, plus the alarm that fires while it is not empty.
module "target_dlq" {
  source = "../../modules/target-dlq"

  environment = local.environment
}

output "target_dlq_arn" {
  value       = module.target_dlq.target_dlq_arn
  description = "ARN of the prod notification target dead-letter queue."
}

# ---
# EventBridge notification rules on the default bus. DMS CDC and the CDC crawlers only
# exist in prod, so only prod passes their names; each DMS resource gets its own rule.
# The names come from infra/dms/orcabus-db and infra/glue-crawler/orcabus-db
# (name_prefix "orcabus-db" and one task / crawler per OrcaBus database).
module "notification_rules" {
  source = "../../modules/notification-rules"

  environment        = local.environment
  topic_arn          = var.slack_topic_arn
  publisher_role_arn = module.publisher_role.publisher_role_arn
  dlq_arn            = module.target_dlq.target_dlq_arn
  disabled_rules     = var.disabled_notification_rules

  dms_replication_instance_ids = ["orcabus-db-replication-instance"]
  dms_replication_task_ids = [
    "orcabus-db-task-filemanager",
    "orcabus-db-task-metadata-manager",
    "orcabus-db-task-sequence-run-manager",
    "orcabus-db-task-workflow-manager",
  ]

  # Add orcavault-db-prod-mart-crawler here once infra/glue-crawler/orcavault-db prod is
  # applied (it is defined there but not deployed yet).
  crawler_names = [
    "orcabus-db-crawler-filemanager",
    "orcabus-db-crawler-metadata-manager",
    "orcabus-db-crawler-sequence-run-manager",
    "orcabus-db-crawler-workflow-manager",
  ]
}

output "notification_rule_names" {
  value       = module.notification_rules.rule_names
  description = "Map of rule key to the prod EventBridge notification rule name."
}
