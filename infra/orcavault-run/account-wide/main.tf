# The OrcaVault runner resources for the environment that is shared.

terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/ecs/orcavault-run/account-wide/terraform.tfstate"
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

# Configure the ecr repository that holds the dbt image.
resource "aws_ecr_repository" "dbt" {
  name                 = "orcavault-run-dbt"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# This cleans up old images that haven't been used in a while.
# See https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html
resource "aws_ecr_lifecycle_policy" "dbt" {
  repository = aws_ecr_repository.dbt.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Archive images older than 90 days."
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePulled"
          countUnit   = "days"
          countNumber = 90
        }
        action = {
          type               = "transition"
          targetStorageClass = "archive"
        }
      },
      {
        rulePriority = 2
        description  = "Delete images archived for a year."
        selection = {
          tagStatus    = "any"
          storageClass = "archive"
          countType    = "sinceImageTransitioned"
          countUnit    = "days"
          countNumber  = 365
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

output "ecr_repository_url" {
  description = "The dbt image should be pushed here and tagged with the orcavault ref."
  value       = aws_ecr_repository.dbt.repository_url
}
