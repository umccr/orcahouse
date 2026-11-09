mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-2"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  crawler_names = ["crawler-a", "crawler-b"]
}

run "a_running_crawl_is_waited_on" {
  assert {
    condition = alltrue([
      output.item_processor.States.StartCrawler.Catch[0].ErrorEquals == ["Glue.CrawlerRunningException"],
      output.item_processor.States.StartCrawler.Catch[0].Next == "WaitForCrawl",
    ])
    error_message = "a crawler that is already running should be waited on, not fail"
  }

  assert {
    condition = alltrue([
      contains(output.item_processor.States.StartCrawler.Retry[0].ErrorEquals, "Glue.CrawlerRunningException"),
      output.item_processor.States.StartCrawler.Retry[0].MaxAttempts == 0,
    ])
    error_message = "starting a crawler that is already running should not be retried"
  }
}

run "every_item_reports" {
  assert {
    condition = alltrue([
      for name, state in output.item_processor.States :
      state.Catch[length(state.Catch) - 1].ErrorEquals == ["States.ALL"] && state.Catch[length(state.Catch) - 1].Next == "Report"
      if state.Type == "Task"
    ])
    error_message = "every error should be reported as the item's status, so the Map always finishes"
  }

  assert {
    condition     = output.item_processor.States.Report.End == true
    error_message = "every item should end with its report"
  }
}

run "a_long_crawl_times_out" {
  variables {
    poll_seconds     = 60
    max_wait_minutes = 30
  }

  assert {
    condition     = output.item_processor.States.IsCrawlFinished.Choices[1].Condition == "{% $crawlPolls >= 30 %}"
    error_message = "a crawl should be reported as TIMEOUT after max_wait_minutes"
  }
}

run "the_policy_is_for_the_crawlers" {
  assert {
    condition = jsonencode(tolist(data.aws_iam_policy_document.crawl[0].statement[0].resources)) == jsonencode([
      "arn:aws:glue:ap-southeast-2:123456789012:crawler/crawler-a",
      "arn:aws:glue:ap-southeast-2:123456789012:crawler/crawler-b",
    ])
    error_message = "the policy should be for the crawlers"
  }
}

run "no_crawlers" {
  variables {
    crawler_names = []
  }

  assert {
    condition     = output.policy_json == null && length(output.items) == 0
    error_message = "without crawlers, there should be no items and no policy"
  }
}
