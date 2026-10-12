"""The run's event, and reading a dbt invocation's run_results.json into it.

https://docs.getdbt.com/reference/artifacts/run-results-json
"""

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, field_serializer
from pydantic.alias_generators import to_camel


class Outcome(StrEnum):
    """How a run went. These are all the outcomes a run can have, which
    stepfunctions.tf names too."""

    SUCCEEDED = "succeeded"
    # Only warn severity tests failed. Nothing was held back.
    WARNED = "warned"
    # Another run was still going, so this one didn't start. Only the state
    # machine gives a run this outcome.
    SKIPPED = "skipped"
    # A model, seed or snapshot didn't build, or an error severity test or a
    # hook failed. Only what depends on a failed node was held back, or
    # everything after it with --fail-fast.
    FAILED = "failed"
    # dbt didn't run to completion, or the request was invalid.
    ERROR = "error"

    @property
    def exit_code(self) -> int:
        # Non-zero fails the Step Functions task.
        return 0 if self in (Outcome.SUCCEEDED, Outcome.WARNED) else 1


class Event(BaseModel):
    """How the run went, for the detail of its EventBridge event. The state
    machine adds the fields every run's event has, such as runId. It's flat and
    already formatted, so that EventBridge input transformers can use it as it
    is."""

    # In camelCase in event.json. A field is checked when it's set, so that a
    # wrong type is an error rather than a value the notifications can't use.
    model_config = ConfigDict(
        alias_generator=to_camel,
        validate_by_name=True,
        serialize_by_alias=True,
        validate_assignment=True,
    )

    outcome: Outcome = Outcome.ERROR
    # Why the outcome is error, otherwise None.
    error: str | None = None
    models_succeeded: int = 0
    models_failed: int = 0
    models_skipped: int = 0
    tests_passed: int = 0
    tests_warned: int = 0
    tests_failed: int = 0
    # Unique IDs, in the order dbt finished them.
    failed_nodes: list[str] = []
    warned_nodes: list[str] = []

    @field_serializer("failed_nodes", "warned_nodes")
    def summarise(self, unique_ids: list[str]) -> str:
        """A short list for a notification, which can't loop over an array, by
        the names people know the nodes by, once each.

        Unique IDs are <type>.<package>.<name>, where a data test also ends with
        a hash, a versioned model with its version, and a unit test has its
        model before its name.
        """
        names = list(dict.fromkeys(u.split(".")[-1 if u.startswith("unit_test.") else 2] for u in unique_ids))
        if len(names) > 10:
            return ", ".join(names[:10]) + f" and {len(names) - 10} more"
        return ", ".join(names)


BUILT_TYPES = {"model", "seed", "snapshot"}
TEST_TYPES = {"test", "unit_test"}

# dbt's NodeStatus values, by what they mean here.
SUCCEEDED_STATUSES = {"success", "pass", "no-op"}
FAILED_STATUSES = {"error", "fail", "runtime error", "partial success"}


def read_results(run_results: dict[str, Any]) -> Event:
    event = Event()
    for result in run_results.get("results", []):
        unique_id, status = result["unique_id"], result["status"]
        succeeded, failed = status in SUCCEEDED_STATUSES, status in FAILED_STATUSES
        # Any node, including an on-run-start or on-run-end hook, such as the
        # CDC watermark's.
        if failed:
            event.failed_nodes.append(unique_id)
        elif status == "warn":
            event.warned_nodes.append(unique_id)

        # Each bool adds 1 or 0.
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
    """dbt exits 1 when a node fails and 2 when it couldn't run at all."""
    if exit_code not in (0, 1):
        return Outcome.ERROR
    if event.failed_nodes:
        return Outcome.FAILED
    # dbt failed without a node failing.
    if exit_code:
        return Outcome.ERROR
    return Outcome.WARNED if event.warned_nodes else Outcome.SUCCEEDED
