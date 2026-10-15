"""Mock dbt and results fixtures."""

import json
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def result(unique_id: str, status: str, message: str | None = None) -> dict[str, Any]:
    """The mock result in run_results.json."""
    return {"unique_id": unique_id, "status": status, "message": message}


def run_results(*results: dict[str, Any]) -> dict[str, Any]:
    """The mock run_results.json."""
    return {"results": list(results)}


@dataclass
class MockDbt:
    code: int = 0
    results: list[dict[str, Any]] | None = field(default_factory=list)
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
