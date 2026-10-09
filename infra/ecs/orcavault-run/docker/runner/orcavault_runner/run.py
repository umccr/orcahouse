"""Running a request and recording how it went.

A run is one dbt command, and its event says how it went. The entrypoint
writes the event to event.json, which the state machine adds to and sends as
the detail of the run's EventBridge event, see stepfunctions.tf. dbt's
run_results.json is only read for the event, and the logs have the rest.
"""

import json
import logging
from pathlib import Path
from typing import Protocol

from pydantic import ConfigDict
from pydantic.alias_generators import to_camel

from .dbt import DbtExit
from .request import RequestError, parse_request
from .results import Counts, Outcome, classify, read_results, resource_type, summarise_nodes

log = logging.getLogger(__name__)

# Long enough for the runner's own errors. dbt's are in the logs.
ERROR_LIMIT = 300


class Event(Counts):
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
    failed_nodes: str = ""
    warned_nodes: str = ""
    positions_advanced: bool | None = None


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


def run_dbt(args: tuple[str, ...], project_dir: Path, dbt: Dbt, event: Event) -> Outcome:
    """Runs dbt, and records how it went in the event."""
    results_path = project_dir / "target" / "run_results.json"
    # A file left by an earlier dbt command, such as one run by hand, would be
    # read as this run's results if dbt fails early.
    results_path.unlink(missing_ok=True)

    dbt_exit = dbt(list(args))
    event.positions_advanced = dbt_exit.positions_advanced

    if not results_path.exists():
        event.error = f"dbt exited with {dbt_exit.code} and wrote no run_results.json, see the logs"
        return Outcome.ERROR

    results = read_results(json.loads(results_path.read_text()))
    for name, count in results.counts:
        setattr(event, name, count)
    event.failed_nodes = summarise_nodes(results.failed_nodes)
    event.warned_nodes = summarise_nodes(results.warned_nodes)

    outcome = classify(dbt_exit.code, results)
    if outcome is Outcome.ERROR:
        hooks = [unique_id for unique_id in results.failed_nodes if resource_type(unique_id) == "operation"]
        if hooks:
            event.error = f"A hook failed: {summarise_nodes(hooks)}"
        else:
            event.error = f"dbt exited with {dbt_exit.code}, see the logs"
    return outcome


def run(raw_request: str, project_dir: Path, dbt: Dbt) -> tuple[Outcome, Event]:
    """Runs the request in the dbt project, and returns its outcome and event."""
    event = Event()

    outcomes: list[Outcome] = []
    try:
        request = parse_request(raw_request)
    except RequestError as e:
        event.error = str(e)
        outcomes.append(Outcome.ERROR)
    else:
        if not dbt.stopping:
            outcomes.append(run_dbt(request.args, project_dir, dbt, event))

    if dbt.stopping:
        event.error = "The run was stopped"
        outcomes.append(Outcome.ERROR)

    outcome = Outcome.worst(outcomes)
    event.outcome = outcome
    if event.error is not None:
        log.error("%s", event.error)
        event.error = one_line(event.error)
    return outcome, event
