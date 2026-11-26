"""Logic for running a request and recording the result."""

import json
import logging
from collections.abc import Sequence
from pathlib import Path
from typing import Protocol

from .request import RequestError, parse_request
from .results import Event, Outcome, classify, read_results

log = logging.getLogger(__name__)


class DbtCommand(Protocol):
    """The protocol for a dbt run, which is used to type the run_dbt here and mock tests."""

    stopping: bool

    def __call__(self, args: Sequence[str]) -> int: ...


def one_line(text: str, limit: int = 300) -> str:
    """The text as one line message without double quotes or backslashes.

    These aren't supported by the EventBridge transformer.
    """
    text = " ".join(text.replace('"', "'").replace("\\", "").split())
    text = "".join(c for c in text if c.isprintable())

    return text if len(text) <= limit else text[: limit - 3] + "..."


def clear_artifacts() -> None:
    """Remove the image's manifest from `dbt parse` and any earlier result, so what's left after is this run's."""
    for artifact in ("manifest.json", "run_results.json"):
        Path("target", artifact).unlink(missing_ok=True)


def run_dbt(args: tuple[str, ...], dbt: DbtCommand) -> Event:
    """Run the dbt command and return the result dbt."""
    code = dbt(args)

    results_path = Path("target", "run_results.json")
    if not results_path.exists():
        return Event(error=f"dbt exited with {code} with no run_results.json, view the logs")

    run_results = json.loads(results_path.read_text())
    event = read_results(run_results)
    event.outcome = classify(code, event)

    if event.outcome is Outcome.ERROR:
        # If this is a skipped model, the message gives the reason.
        reasons = (r["message"] for r in run_results.get("results", []) if r["status"] == "skipped" and r["message"])
        event.error = next(reasons, f"dbt exited with {code}, view the logs")
    return event


def finish(event: Event, dbt: DbtCommand) -> Event:
    """Make a stopped run an error, and put the error on one line for the event."""
    if dbt.stopping:
        event.error = "The run was stopped"
        event.outcome = Outcome.ERROR

    if event.error is not None:
        log.error("%s", event.error)
        event.error = one_line(event.error)

    return event


def run(raw_request: str, dbt: DbtCommand) -> Event:
    """Run the dbt request and return the event.

    The working directory is expected to be the dbt project.
    """
    clear_artifacts()

    try:
        args = parse_request(raw_request)
    except RequestError as e:
        event = Event(error=str(e))
    else:
        event = run_dbt(args, dbt)

    return finish(event, dbt)
