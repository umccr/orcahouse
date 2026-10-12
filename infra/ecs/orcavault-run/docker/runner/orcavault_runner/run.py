"""Running a request and recording how it went.

A run is one dbt command, and its event says how it went. The entrypoint
writes the event to event.json, which the state machine adds to and sends as
the detail of the run's EventBridge event, see stepfunctions.tf. dbt's
run_results.json is only read for the event, and the logs have the rest.
"""

import json
import logging
from pathlib import Path

from .dbt import Dbt
from .request import RequestError, parse_request
from .results import Event, Outcome, classify, read_results

log = logging.getLogger(__name__)


def one_line(text: str, limit: int = 300) -> str:
    """The text as one short line, without double quotes or backslashes.

    An EventBridge input transformer, which doesn't escape what it puts into a
    JSON string, can then use it. The limit is long enough for the runner's own
    errors and dbt's reasons for a skip. dbt's errors are in the logs.
    """
    text = " ".join(text.replace('"', "'").replace("\\", "").split())
    text = "".join(c for c in text if c.isprintable())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def run_dbt(args: tuple[str, ...], dbt: Dbt) -> Event:
    """Runs dbt, and returns how it went."""
    results_path = Path("target", "run_results.json")
    # A file left by an earlier dbt command, such as one run by hand, would be
    # read as this run's results if dbt fails early.
    results_path.unlink(missing_ok=True)

    code = dbt(args)

    if not results_path.exists():
        return Event(error=f"dbt exited with {code} and wrote no run_results.json, see the logs")

    run_results = json.loads(results_path.read_text())
    event = read_results(run_results)
    event.outcome = classify(code, event)
    if event.outcome is Outcome.ERROR:
        # Such as that an ephemeral model failed, which dbt gives as the reason
        # it skipped a node that depends on it.
        reasons = (r["message"] for r in run_results.get("results", []) if r["status"] == "skipped" and r["message"])
        event.error = next(reasons, f"dbt exited with {code}, see the logs")
    return event


def run(raw_request: str, dbt: Dbt) -> Event:
    """Runs the request in the dbt project, and returns its event.

    The dbt project is the working directory.
    """
    try:
        request = parse_request(raw_request)
    except RequestError as e:
        event = Event(error=str(e))
    else:
        event = run_dbt(request.args, dbt)

    # An error, however far dbt got.
    if dbt.stopping:
        event.error = "The run was stopped"
        event.outcome = Outcome.ERROR

    if event.error is not None:
        log.error("%s", event.error)
        event.error = one_line(event.error)
    return event
