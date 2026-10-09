"""Stand-ins for dbt and its run_results.json."""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from orcavault_runner.dbt import DbtExit


def result(unique_id: str, status: str) -> dict[str, Any]:
    """One entry of run_results.json, with only the fields the runner reads."""
    return {"unique_id": unique_id, "status": status}


def run_results(*results: dict[str, Any]) -> dict[str, Any]:
    return {"results": list(results)}


@dataclass
class FakeDbt:
    project_dir: Path
    code: int = 0
    # None writes no run_results.json.
    results: list[dict[str, Any]] | None = field(default_factory=list)
    positions_advanced: bool | None = None
    # Stopped while dbt runs, as when ECS stops the task.
    stop: bool = False
    stopping: bool = False
    calls: list[list[str]] = field(default_factory=list)

    def __call__(self, args: list[str]) -> DbtExit:
        self.calls.append(args)
        if self.results is not None:
            path = self.project_dir / "target" / "run_results.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(run_results(*self.results)))
        self.stopping = self.stop
        return DbtExit(self.code, self.positions_advanced)
