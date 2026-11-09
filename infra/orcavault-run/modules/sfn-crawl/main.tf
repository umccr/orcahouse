# The states that start one Glue crawler and wait for its crawl to finish. They're a Map's
# ItemProcessor, where each item is a crawler's name, so the state and variable names can't
# collide with the stage around them. This module only creates states, not resources.
#
# A crawler that is already running isn't started again, the states wait for that crawl
# instead. Every error is caught, so the Map always finishes, and each item's output is
# {crawler, status, error}. status is the crawl's SUCCEEDED, FAILED or CANCELLED, TIMEOUT
# when the crawl took longer than max_wait_minutes, or ERROR when the crawler couldn't be
# started or read.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45.0"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  max_polls = ceil(var.max_wait_minutes * 60 / var.poll_seconds)

  crawler_arns = [
    for name in var.crawler_names :
    "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:crawler/${name}"
  ]

  retry_api_errors = {
    ErrorEquals     = ["States.ALL"]
    IntervalSeconds = 10
    MaxAttempts     = 3
    BackoffRate     = 2
  }

  # The crawl couldn't be followed, so it's reported with the error's name.
  catch_as_error = {
    ErrorEquals = ["States.ALL"]
    Assign      = { crawlStatus = "ERROR", crawlError = "{% $states.errorOutput.Error %}" }
    Next        = "Report"
  }

  item_processor = {
    StartAt = "Init"
    States = {
      Init = {
        Type   = "Pass"
        Assign = { crawlName = "{% $states.input %}", crawlPolls = 0 }
        Next   = "ReadLastCrawl"
      }

      # A new crawl has finished once the last crawl's start time differs from this one.
      # Comparing the values avoids depending on how the timestamps are formatted.
      ReadLastCrawl = {
        Type      = "Task"
        Resource  = "arn:aws:states:::aws-sdk:glue:getCrawler"
        Arguments = { Name = "{% $crawlName %}" }
        Assign = {
          crawlPrevious = "{% $exists($states.result.Crawler.LastCrawl.StartTime) ? $states.result.Crawler.LastCrawl.StartTime : null %}"
        }
        Output = {}
        Retry  = [local.retry_api_errors]
        Catch  = [local.catch_as_error]
        Next   = "StartCrawler"
      }

      StartCrawler = {
        Type      = "Task"
        Resource  = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Arguments = { Name = "{% $crawlName %}" }
        Output    = {}
        # The first retrier matches first, so these errors are never retried.
        Retry = [
          {
            ErrorEquals = ["Glue.CrawlerRunningException", "Glue.EntityNotFoundException"]
            MaxAttempts = 0
          },
          local.retry_api_errors,
        ]
        # Another crawl is running, such as the other environment's, so this waits for it.
        Catch = [
          {
            ErrorEquals = ["Glue.CrawlerRunningException"]
            Next        = "WaitForCrawl"
          },
          local.catch_as_error,
        ]
        Next = "WaitForCrawl"
      }

      WaitForCrawl = {
        Type    = "Wait"
        Seconds = var.poll_seconds
        Next    = "ReadCrawler"
      }

      ReadCrawler = {
        Type      = "Task"
        Resource  = "arn:aws:states:::aws-sdk:glue:getCrawler"
        Arguments = { Name = "{% $crawlName %}" }
        Assign    = { crawlPolls = "{% $crawlPolls + 1 %}" }
        Output    = "{% $states.result.Crawler %}"
        Retry     = [local.retry_api_errors]
        Catch     = [local.catch_as_error]
        Next      = "IsCrawlFinished"
      }

      IsCrawlFinished = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $states.input.State = 'READY' and $exists($states.input.LastCrawl.StartTime) and $states.input.LastCrawl.StartTime != $crawlPrevious %}"
            Next      = "CrawlFinished"
          },
          {
            Condition = "{% $crawlPolls >= ${local.max_polls} %}"
            Next      = "CrawlTimedOut"
          }
        ]
        Default = "WaitForCrawl"
      }

      CrawlFinished = {
        Type = "Pass"
        Assign = {
          crawlStatus = "{% $states.input.LastCrawl.Status %}"
          crawlError  = "{% $exists($states.input.LastCrawl.ErrorMessage) ? $states.input.LastCrawl.ErrorMessage : null %}"
        }
        Next = "Report"
      }

      # The crawl carries on, and its own result is still in the Glue console.
      CrawlTimedOut = {
        Type = "Pass"
        Assign = {
          crawlStatus = "TIMEOUT"
          crawlError  = "The crawl was still running after ${var.max_wait_minutes} minutes"
        }
        Next = "Report"
      }

      Report = {
        Type   = "Pass"
        Output = "{% { 'crawler': $crawlName, 'status': $crawlStatus, 'error': $crawlError } %}"
        End    = true
      }
    }
  }
}

data "aws_iam_policy_document" "crawl" {
  count = length(var.crawler_names) > 0 ? 1 : 0

  statement {
    sid       = "StartAndReadCrawlers"
    effect    = "Allow"
    actions   = ["glue:StartCrawler", "glue:GetCrawler"]
    resources = local.crawler_arns
  }
}
