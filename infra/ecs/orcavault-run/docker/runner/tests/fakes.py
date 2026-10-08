"""Stand-ins for dbt and its run_results.json."""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from orcavault_runner.dbt import DbtExit


def result(unique_id: str, status: str) -> dict[str, Any]:
    """One entry of run_results.json, with the fields the runner doesn't read
    filled in the way dbt 1.11 writes them."""
    return {
        "status": status,
        "timing": [],
        "thread_id": "Thread-1",
        "execution_time": 0.5,
        "adapter_response": {},
        "message": None,
        "failures": 1 if status in ("fail", "warn") else None,
        "unique_id": unique_id,
        "compiled": True,
        "relation_name": None,
        "batch_results": None,
    }


def run_results(*results: dict[str, Any]) -> dict[str, Any]:
    return {
        "metadata": {
            "dbt_schema_version": "https://schemas.getdbt.com/dbt/run-results/v6.json",
            "dbt_version": "1.11.12",
            "invocation_id": "00000000-0000-0000-0000-000000000000",
        },
        "results": list(results),
        "elapsed_time": 1.0,
        "args": {"which": "build"},
    }


@dataclass
class Invocation:
    """What a stand-in dbt invocation does: its exit code, the results it
    writes, if any, and what it logs about the CDC positions."""

    code: int = 0
    results: list[dict[str, Any]] | None = field(default_factory=list)
    positions_advanced: bool | None = None
    stop: bool = False


class FakeDbt:
    def __init__(self, project_dir: Path, *invocations: Invocation) -> None:
        self.project_dir = project_dir
        self.invocations = list(invocations)
        self.calls: list[list[str]] = []
        self.stopping = False

    def __call__(self, args: list[str]) -> DbtExit:
        self.calls.append(args)
        invocation = self.invocations.pop(0)
        if invocation.results is not None:
            path = self.project_dir / "target" / "run_results.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(run_results(*invocation.results)))
        if invocation.stop:
            self.stopping = True
        return DbtExit(invocation.code, invocation.positions_advanced)
