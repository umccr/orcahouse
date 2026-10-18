"""The results of a run which are based on the dbt run_results.json.

See https://docs.getdbt.com/reference/artifacts/run-results-json
"""

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, field_serializer
from pydantic.alias_generators import to_camel


class Outcome(StrEnum):
    """The outcome of a run."""

    SUCCEEDED = "succeeded"
    # Only warn severity tests failed.
    WARNED = "warned"
    # The run was skipped because another run was still going.
    SKIPPED = "skipped"
    # A model, seed or snapshot didn't build, or an error severity test or a
    # hook failed.
    FAILED = "failed"
    # The dbt didn't run to completion.
    ERROR = "error"

    @property
    def exit_code(self) -> int:
        # Non-zero fails the Step Functions task.
        return 0 if self in (Outcome.SUCCEEDED, Outcome.WARNED) else 1


# The amount of nodes the event can format.
NODES_LISTED = 10


class Event(BaseModel):
    """The event result which has details for EventBridge."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        validate_by_name=True,
        serialize_by_alias=True,
        validate_assignment=True,
    )

    outcome: Outcome = Outcome.ERROR
    # Why the outcome is an error if set.
    error: str | None = None
    models_succeeded: int = 0
    models_failed: int = 0
    models_skipped: int = 0
    tests_passed: int = 0
    tests_warned: int = 0
    tests_failed: int = 0
    # The unique IDs for failed/warned nodes.
    failed_nodes: list[str] = []
    warned_nodes: list[str] = []

    @field_serializer("failed_nodes", "warned_nodes")
    def summarise(self, unique_ids: list[str]) -> str:
        """Summarise the nodes as a short list for a notification."""
        names = list(dict.fromkeys(u.split(".")[-1 if u.startswith("unit_test.") else 2] for u in unique_ids))

        if len(names) > NODES_LISTED:
            return ", ".join(names[:NODES_LISTED]) + f" and {len(names) - NODES_LISTED} more"

        return ", ".join(names)


BUILT_TYPES = {"model", "seed", "snapshot"}
TEST_TYPES = {"test", "unit_test"}

# These are the NodeStatus values from the dbt command.
SUCCEEDED_STATUSES = {"success", "pass", "no-op", "reused"}
FAILED_STATUSES = {"error", "fail", "runtime error", "partial success"}


def read_results(run_results: dict[str, Any]) -> Event:
    """Read the results into an event."""
    event = Event()
    for result in run_results.get("results", []):
        unique_id, status = result["unique_id"], result["status"]
        succeeded, failed = status in SUCCEEDED_STATUSES, status in FAILED_STATUSES

        if failed:
            event.failed_nodes.append(unique_id)
        elif status == "warn":
            event.warned_nodes.append(unique_id)

        kind = unique_id.split(".", 1)[0]
        if kind in BUILT_TYPES:
            event.models_succeeded += succeeded
            event.models_failed += failed
            event.models_skipped += status == "skipped"
        elif kind in TEST_TYPES:
            event.tests_passed += succeeded
            event.tests_warned += status == "warn"
            event.tests_failed += failed

    return event


def classify(exit_code: int, event: Event) -> Outcome:
    """Classify the run outcome from the dbt exit code and results."""
    if exit_code not in (0, 1):
        return Outcome.ERROR
    if event.failed_nodes:
        return Outcome.FAILED

    # The dbt command exited with 1, which happens if dbt fails without a node
    # failing, such as an ephemeral model failure.
    if exit_code:
        return Outcome.ERROR

    return Outcome.WARNED if event.warned_nodes else Outcome.SUCCEEDED
