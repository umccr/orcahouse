"""Running a request and recording how it went.

A run is one dbt command, and its event says how it went. The entrypoint
writes the event to event.json, which the state machine sends as the detail of
the run's EventBridge event, see stepfunctions.tf. dbt's run_results.json is
only read for the event, and the logs have the rest.
"""

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from .dbt import DbtExit
from .request import RequestError, parse_request
from .results import Counts, Outcome, classify, read_results, resource_type, summarise_nodes

log = logging.getLogger(__name__)

# Long enough for the runner's own errors. dbt's are in the logs.
ERROR_LIMIT = 300


@dataclass(frozen=True)
class Config:
    run_id: str
    environment: str
    project_dir: Path
    orcavault_ref: str
    logs_url: str | None = None


class Dbt(Protocol):
    """What the runner needs from dbt.Dbt, so that tests can stand in for it."""

    stopping: bool

    def __call__(self, args: list[str]) -> DbtExit: ...


def one_line(text: str, limit: int = ERROR_LIMIT) -> str:
    """The text as one short line without double quotes or backslashes, so that
    an EventBridge input transformer, which doesn't escape what it puts into a
    JSON string, can use it."""
    text = " ".join(text.replace('"', "'").replace("\\", "").split())
    text = "".join(c for c in text if c.isprintable())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def run_dbt(args: tuple[str, ...], config: Config, dbt: Dbt, event: dict[str, Any]) -> Outcome:
    """Runs dbt, and records how it went in the event."""
    results_path = config.project_dir / "target" / "run_results.json"
    # A file left by an earlier dbt command, such as one run by hand, would be
    # read as this run's results if dbt fails early.
    results_path.unlink(missing_ok=True)

    dbt_exit = dbt(list(args))
    event["positionsAdvanced"] = dbt_exit.positions_advanced

    if not results_path.exists():
        event["error"] = f"dbt exited with {dbt_exit.code} and wrote no run_results.json, see the logs"
        return Outcome.ERROR

    results = read_results(json.loads(results_path.read_text()))
    event.update(results.counts.to_json())
    event["failedNodes"] = summarise_nodes(results.failed_nodes)
    event["warnedNodes"] = summarise_nodes(results.warned_nodes)

    outcome = classify(dbt_exit.code, results)
    if outcome is Outcome.ERROR:
        hooks = [unique_id for unique_id in results.failed_nodes if resource_type(unique_id) == "operation"]
        if hooks:
            event["error"] = f"A hook failed: {summarise_nodes(hooks)}"
        else:
            event["error"] = f"dbt exited with {dbt_exit.code}, see the logs"
    return outcome


def run(raw_request: str, config: Config, dbt: Dbt) -> tuple[Outcome, dict[str, Any]]:
    """Runs the request, and returns its outcome and event.

    The event is the detail of the run's EventBridge event, less executionUrl,
    which the state machine adds. It's flat and already formatted, so that
    EventBridge input transformers can use it as it is.
    """
    started_at = datetime.now(timezone.utc)
    event: dict[str, Any] = {
        "environment": config.environment,
        "outcome": Outcome.ERROR,
        # Why the outcome is error, otherwise None.
        "error": None,
        "runId": config.run_id,
        **Counts().to_json(),
        "failedNodes": "",
        "warnedNodes": "",
        "positionsAdvanced": None,
        "orcavaultRef": config.orcavault_ref,
        "durationMinutes": 0,
        "logsUrl": config.logs_url,
    }

    outcomes: list[Outcome] = []
    try:
        request = parse_request(raw_request)
    except RequestError as e:
        event["error"] = str(e)
        outcomes.append(Outcome.ERROR)
    else:
        if not dbt.stopping:
            outcomes.append(run_dbt(request.args, config, dbt, event))

    if dbt.stopping:
        event["error"] = "The run was stopped"
        outcomes.append(Outcome.ERROR)

    outcome = Outcome.worst(outcomes)
    event["outcome"] = outcome
    if event["error"] is not None:
        log.error("%s", event["error"])
        event["error"] = one_line(event["error"])
    event["durationMinutes"] = round((datetime.now(timezone.utc) - started_at).total_seconds() / 60)
    return outcome, event
