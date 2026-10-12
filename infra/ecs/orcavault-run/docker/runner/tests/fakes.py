"""Stand-ins for dbt and its run_results.json."""

import json
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def result(unique_id: str, status: str) -> dict[str, Any]:
    """One entry of run_results.json, with only the fields the runner reads."""
    return {"unique_id": unique_id, "status": status}


def run_results(*results: dict[str, Any]) -> dict[str, Any]:
    return {"results": list(results)}


@dataclass
class FakeDbt:
    code: int = 0
    # None writes no run_results.json.
    results: list[dict[str, Any]] | None = field(default_factory=list)
    # Stopped while dbt runs, as when ECS stops the task.
    stop: bool = False
    stopping: bool = False
    calls: list[Sequence[str]] = field(default_factory=list)

    def __call__(self, args: Sequence[str]) -> int:
        self.calls.append(args)
        if self.results is not None:
            path = Path("target", "run_results.json")
            path.parent.mkdir(exist_ok=True)
            path.write_text(json.dumps(run_results(*self.results)))
        self.stopping = self.stop
        return self.code
