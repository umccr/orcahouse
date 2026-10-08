"""Running a request and recording how it went.

A run is one dbt command. Its run_results.json is kept, and the run ends by
writing summary.json and event.json. The state machine sends event.json as the
detail of the run's EventBridge event, see stepfunctions.tf. It's kept apart
from the summary, which lists every failed node, because a state can only read
256 KiB.
"""

import json
import logging
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from .dbt import DbtExit
from .request import Request, RequestError, parse_request
from .results import Counts, Outcome, RunResults, classify, read_results, summarise_nodes
from .store import Store, event_key, results_key, summary_key

log = logging.getLogger(__name__)


class RunError(Exception):
    """The run can't go ahead as requested."""


@dataclass(frozen=True)
class Config:
    run_id: str
    environment: str
    project_dir: Path
    orcavault_ref: str
    orcavault_commit: str
    logs_url: str | None = None


class Dbt(Protocol):
    """What the runner needs from dbt.Dbt, so that tests can stand in for it."""

    stopping: bool

    def __call__(self, args: list[str]) -> DbtExit: ...


@dataclass(frozen=True)
class Plan:
    """The dbt command a run makes. For a retry, the args are just retry, and
    dbt reads the rest from the results of the run retry_of."""

    args: tuple[str, ...]
    retry_of: str | None = None


def plan(request: Request, store: Store) -> Plan:
    """What to run. A retry picks up an earlier run where it failed."""
    if request.retry is None:
        return Plan(request.args)

    run_id = request.retry
    try:
        previous = store.get_json(summary_key(run_id))
    except KeyError as e:
        raise RunError(f"Can't retry run {run_id}: it has no summary at {e}") from e

    if Outcome(previous["outcome"]).ok:
        raise RunError(f"Can't retry run {run_id}: it {previous['outcome']}, so nothing failed")
    if previous["args"] is None:
        raise RunError(f"Can't retry run {run_id}: it didn't run dbt, because: {previous['error']}")
    if previous["retryable"]:
        return Plan(("retry",), retry_of=run_id)
    # dbt retry can't pick it up, so it runs again whole. If it was a retry
    # itself, that's dbt retry from the same results as before.
    return Plan(tuple(previous["args"]), previous["retryOf"])


def run_dbt(planned: Plan, config: Config, store: Store, dbt: Dbt, summary: dict[str, Any]) -> Outcome:
    """Runs dbt as planned, and records how it went in the summary."""
    summary["args"] = list(planned.args)
    summary["retryOf"] = planned.retry_of

    results_path = config.project_dir / "target" / "run_results.json"
    # A file left by an earlier dbt command, such as one run by hand, would be
    # read as this run's results if dbt fails early.
    results_path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory() as state_dir:
        args = list(planned.args)
        if planned.retry_of is not None:
            try:
                store.get_file(results_key(planned.retry_of), Path(state_dir) / "run_results.json")
            except KeyError as e:
                summary["error"] = f"No results to retry at {e}"
                log.error(summary["error"])
                return Outcome.ERROR
            args += ["--state", state_dir]
        dbt_exit = dbt(args)

    summary["exitCode"] = dbt_exit.code
    summary["positionsAdvanced"] = dbt_exit.positions_advanced

    results: RunResults | None = None
    if results_path.exists():
        run_results = json.loads(results_path.read_text())
        results = read_results(run_results)
        key = results_key(config.run_id)
        store.put_file(key, results_path)
        summary["resultsKey"] = key
        # Whether dbt retry can pick up where this run left off. Otherwise a
        # retry runs it again whole. dbt retry reruns only the nodes in
        # run_results.json, and when dbt is interrupted it leaves out the ones it
        # hadn't started. It also refuses results without any nodes.
        summary["retryable"] = bool(run_results["results"]) and not dbt.stopping
        summary["counts"] = results.counts.to_json()
        summary["failedNodes"] = results.failed_nodes
        summary["warnedNodes"] = results.warned_nodes
    else:
        summary["error"] = f"dbt exited with {dbt_exit.code} and wrote no run_results.json, see the logs"

    return classify(dbt_exit.code, results)


def event_detail(summary: dict[str, Any], duration_minutes: int) -> dict[str, Any]:
    """The detail of the run's EventBridge event, less executionUrl, which the
    state machine adds. It's flat and already formatted, so that EventBridge
    input transformers can use it as it is."""
    return {
        "environment": summary["environment"],
        "outcome": summary["outcome"],
        "runId": summary["runId"],
        **summary["counts"],
        "failedNodes": summarise_nodes(summary["failedNodes"]),
        "warnedNodes": summarise_nodes(summary["warnedNodes"]),
        "positionsAdvanced": summary["positionsAdvanced"],
        "orcavaultRef": summary["orcavaultRef"],
        "durationMinutes": duration_minutes,
        "logsUrl": summary["logsUrl"],
    }


def run(raw_request: str, config: Config, store: Store, dbt: Dbt) -> dict[str, Any]:
    """Runs the request and writes its summary, which it also returns."""
    started_at = datetime.now(timezone.utc)
    summary: dict[str, Any] = {
        "runId": config.run_id,
        "environment": config.environment,
        "outcome": Outcome.ERROR.value,
        "orcavaultRef": config.orcavault_ref,
        "orcavaultCommit": config.orcavault_commit,
        "startedAt": started_at.isoformat(),
        "finishedAt": None,
        "request": None,
        # What dbt was asked to run, which a retry of this run reads.
        "args": None,
        "retryOf": None,
        "exitCode": None,
        "resultsKey": None,
        "retryable": False,
        "counts": Counts().to_json(),
        "failedNodes": [],
        "warnedNodes": [],
        "positionsAdvanced": None,
        "logsUrl": config.logs_url,
        "error": None,
        "event": None,
    }

    outcomes: list[Outcome] = []
    try:
        request = parse_request(raw_request)
        summary["request"] = request.to_json()
        planned = plan(request, store)
    except (RequestError, RunError) as e:
        log.error("%s", e)
        summary["error"] = str(e)
        outcomes.append(Outcome.ERROR)
    else:
        if not dbt.stopping:
            outcomes.append(run_dbt(planned, config, store, dbt, summary))

    if dbt.stopping:
        summary["error"] = "The run was stopped"
        outcomes.append(Outcome.ERROR)

    finished_at = datetime.now(timezone.utc)
    summary["outcome"] = Outcome.worst(outcomes).value
    summary["finishedAt"] = finished_at.isoformat()
    summary["event"] = event_detail(summary, round((finished_at - started_at).total_seconds() / 60))

    store.put_json(event_key(config.run_id), summary["event"])
    store.put_json(summary_key(config.run_id), summary)
    log.info("Run %s: %s, summary at %s", config.run_id, summary["outcome"], store.location(summary_key(config.run_id)))
    return summary
