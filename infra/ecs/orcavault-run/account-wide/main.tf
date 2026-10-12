# The OrcaVault run's resources that every environment shares, created once
# for the account. See the README.

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

# --- The dbt image.
#
# One repository for every environment, so that prod runs the very image dev
# ran: an image is built once for each orcavault ref, and a release reaches
# prod by applying it with the ref dev has. Building the ref again could
# resolve different dependencies.

resource "aws_ecr_repository" "dbt" {
  name                 = "orcavault-run-dbt"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# An environment pulls its image on every run, so the images in use stay. One
# that no environment has pulled for 90 days is archived, and deleted a year
# later. Keeping only the newest images instead could delete the one prod runs
# while dev moves ahead of it.
#
# https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html
resource "aws_ecr_lifecycle_policy" "dbt" {
  repository = aws_ecr_repository.dbt.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Archive images no environment has pulled for 90 days."
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
  description = "Push the dbt image here, tagged with its orcavault ref."
  value       = aws_ecr_repository.dbt.repository_url
}
