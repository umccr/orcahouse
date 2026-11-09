mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-2"
    }
  }
}

variables {
  environment        = "prod"
  event_source       = "orcahouse.orcavault"
  event_detail_type  = "OrcaVaultTestFinished"
  succeeded_outcomes = ["succeeded", "degraded"]
  extra_fields = {
    stageField = "'value'"
  }
}

run "every_event_has_the_same_fields" {
  assert {
    condition = alltrue([
      for field in ["environment", "runId", "downstream", "durationMinutes", "executionUrl", "stageField"] :
      strcontains(output.states.AddRunFields.Assign.detail, "'${field}': ")
    ])
    error_message = "every event should have the fields every stage's event has, and the stage's own"
  }

  assert {
    condition     = strcontains(output.states.AddRunFields.Assign.detail, "'downstream': $states.context.Execution.Input.downstream = true")
    error_message = "downstream should only be true when the execution was started with {\"downstream\": true}"
  }
}

run "every_execution_sends_its_event" {
  assert {
    condition = alltrue([
      output.start_at == "AddRunFields",
      output.states.AddRunFields.Next == "SendEvent",
      output.states.SendEvent.Next == "Finish",
      output.states.SendEvent.Catch[0].Next == "Finish",
    ])
    error_message = "the event should be sent before finishing, and a failure to send it should still finish with the outcome"
  }

  assert {
    condition = alltrue([
      output.states.SendEvent.Arguments.Entries[0].Source == "orcahouse.orcavault",
      output.states.SendEvent.Arguments.Entries[0].DetailType == "OrcaVaultTestFinished",
    ])
    error_message = "the event should be the stage's"
  }
}

run "outcomes_finish_the_execution" {
  assert {
    condition     = output.states.Finish.Choices[0].Condition == "{% $detail.outcome in [\"succeeded\",\"degraded\"] %}"
    error_message = "only the succeeded outcomes should succeed the execution"
  }

  assert {
    condition     = output.states.Finish.Default == "Failed" && output.states.Failed.Error == "{% $detail.outcome %}"
    error_message = "any other outcome should fail the execution with the outcome as its error"
  }
}
