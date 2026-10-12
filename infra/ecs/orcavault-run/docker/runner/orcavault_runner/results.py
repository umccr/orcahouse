"""Reading a dbt invocation's run_results.json into counts and an outcome.

https://docs.getdbt.com/reference/artifacts/run-results-json
"""

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

from pydantic import BaseModel


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
        # Non-zero fails the Step Functions task, the same as dbt's own codes.
        return {Outcome.SUCCEEDED: 0, Outcome.WARNED: 0, Outcome.ERROR: 2}.get(self, 1)


BUILT_TYPES = {"model", "seed", "snapshot"}
TEST_TYPES = {"test", "unit_test"}

# dbt's NodeStatus values, by what they mean here.
SUCCEEDED_STATUSES = {"success", "pass", "no-op"}
FAILED_STATUSES = {"error", "fail", "runtime error", "partial success"}


class Counts(BaseModel):
    """A pydantic model, so that the run's event can have the counts as its
    own fields, see run.Event."""

    models_succeeded: int = 0
    models_failed: int = 0
    models_skipped: int = 0
    tests_passed: int = 0
    tests_warned: int = 0
    tests_failed: int = 0


@dataclass
class RunResults:
    counts: Counts = field(default_factory=Counts)
    # Unique IDs, in the order dbt finished them.
    failed_nodes: list[str] = field(default_factory=list)
    warned_nodes: list[str] = field(default_factory=list)


def resource_type(unique_id: str) -> str:
    return unique_id.split(".", 1)[0]


def read_results(run_results: dict[str, Any]) -> RunResults:
    results = RunResults()
    counts = results.counts
    for result in run_results.get("results", []):
        unique_id, status = result["unique_id"], result["status"]
        succeeded, failed = status in SUCCEEDED_STATUSES, status in FAILED_STATUSES
        # Any node, including an on-run-start or on-run-end hook, such as the
        # CDC watermark's.
        if failed:
            results.failed_nodes.append(unique_id)
        elif status == "warn":
            results.warned_nodes.append(unique_id)

        # Each bool adds 1 or 0.
        kind = resource_type(unique_id)
        if kind in BUILT_TYPES:
            counts.models_succeeded += succeeded
            counts.models_failed += failed
            counts.models_skipped += status == "skipped"
        elif kind in TEST_TYPES:
            counts.tests_passed += succeeded
            counts.tests_warned += status == "warn"
            counts.tests_failed += failed
    return results


def classify(exit_code: int, results: RunResults | None) -> Outcome:
    """dbt exits 1 when a node fails and 2 when it couldn't run at all."""
    if results is None or exit_code not in (0, 1):
        return Outcome.ERROR
    if results.failed_nodes:
        return Outcome.FAILED
    # dbt failed without a node failing.
    if exit_code:
        return Outcome.ERROR
    return Outcome.WARNED if results.warned_nodes else Outcome.SUCCEEDED


def node_name(unique_id: str) -> str:
    """The name people know a node by, from its unique ID.

    Unique IDs are <type>.<package>.<name>, where a data test also ends with a
    hash and a unit test has its model before its name.
    """
    parts = unique_id.split(".")
    if parts[0] == "test" and len(parts) > 3:
        return parts[2]
    return parts[-1]


def summarise_nodes(unique_ids: list[str], limit: int = 10) -> str:
    """A short list for a notification, which can't loop over an array."""
    names = list(dict.fromkeys(node_name(unique_id) for unique_id in unique_ids))
    text = ", ".join(names[:limit])
    if len(names) > limit:
        text += f" and {len(names) - limit} more"
    return text
