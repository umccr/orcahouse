"""Reading a dbt invocation's run_results.json into counts and an outcome.

https://docs.getdbt.com/reference/artifacts/run-results-json
"""

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class Outcome(StrEnum):
    """How a run went, from best to worst."""

    SUCCEEDED = "succeeded"
    # Only warn severity tests failed. Nothing was held back.
    WARNED = "warned"
    # An error severity test failed. Only what depends on the tested model
    # was held back, or everything after it with --fail-fast.
    TESTS_FAILED = "tests_failed"
    # A model, seed or snapshot failed to build.
    MODELS_FAILED = "models_failed"
    # dbt didn't run to completion, or the request was invalid.
    ERROR = "error"

    @property
    def ok(self) -> bool:
        return self in (Outcome.SUCCEEDED, Outcome.WARNED)

    @property
    def exit_code(self) -> int:
        # Non-zero fails the Step Functions task, the same as dbt's own codes.
        return {Outcome.SUCCEEDED: 0, Outcome.WARNED: 0, Outcome.ERROR: 2}.get(self, 1)

    @classmethod
    def worst(cls, outcomes: list["Outcome"]) -> "Outcome":
        order = list(cls)
        return max(outcomes, key=order.index, default=cls.SUCCEEDED)


BUILT_TYPES = {"model", "seed", "snapshot"}
TEST_TYPES = {"test", "unit_test"}

# dbt's NodeStatus values, by what they mean here.
SUCCEEDED_STATUSES = {"success", "pass", "no-op"}
FAILED_STATUSES = {"error", "fail", "runtime error", "partial success"}


@dataclass
class Counts:
    models_succeeded: int = 0
    models_failed: int = 0
    models_skipped: int = 0
    tests_passed: int = 0
    tests_warned: int = 0
    tests_failed: int = 0

    def to_json(self) -> dict[str, int]:
        return {
            "modelsSucceeded": self.models_succeeded,
            "modelsFailed": self.models_failed,
            "modelsSkipped": self.models_skipped,
            "testsPassed": self.tests_passed,
            "testsWarned": self.tests_warned,
            "testsFailed": self.tests_failed,
        }


@dataclass
class RunResults:
    counts: Counts = field(default_factory=Counts)
    # Unique IDs, in the order dbt finished them.
    failed_nodes: list[str] = field(default_factory=list)
    warned_nodes: list[str] = field(default_factory=list)
    hook_failed: bool = False


def resource_type(unique_id: str) -> str:
    return unique_id.split(".", 1)[0]


def read_results(run_results: dict[str, Any]) -> RunResults:
    results = RunResults()
    counts = results.counts
    for result in run_results.get("results", []):
        unique_id = result["unique_id"]
        status = result["status"]
        kind = resource_type(unique_id)

        if kind in BUILT_TYPES:
            if status in SUCCEEDED_STATUSES:
                counts.models_succeeded += 1
            elif status in FAILED_STATUSES:
                counts.models_failed += 1
                results.failed_nodes.append(unique_id)
            elif status == "skipped":
                counts.models_skipped += 1
        elif kind in TEST_TYPES:
            if status in SUCCEEDED_STATUSES:
                counts.tests_passed += 1
            elif status == "warn":
                counts.tests_warned += 1
                results.warned_nodes.append(unique_id)
            elif status in FAILED_STATUSES:
                counts.tests_failed += 1
                results.failed_nodes.append(unique_id)
        elif kind == "operation" and status in FAILED_STATUSES:
            # An on-run-start or on-run-end hook, such as the CDC watermark.
            results.hook_failed = True
            results.failed_nodes.append(unique_id)
    return results


def classify(exit_code: int, results: RunResults | None) -> Outcome:
    """dbt exits 1 when a node fails and 2 when it couldn't run at all."""
    if results is None or exit_code not in (0, 1):
        return Outcome.ERROR
    counts = results.counts
    if counts.models_failed:
        return Outcome.MODELS_FAILED
    if counts.tests_failed:
        return Outcome.TESTS_FAILED
    if exit_code != 0 or results.hook_failed:
        return Outcome.ERROR
    if counts.tests_warned:
        return Outcome.WARNED
    return Outcome.SUCCEEDED


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
