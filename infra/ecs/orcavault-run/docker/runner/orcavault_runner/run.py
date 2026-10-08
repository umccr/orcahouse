"""Running a request's steps and recording how they went.

Each step's run_results.json is kept, and the run ends by writing summary.json
and event.json. The state machine sends event.json as the detail of the run's
EventBridge event, see stepfunctions.tf. It's kept apart from the summary, which
lists every failed node, because a state can only read 256 KiB.
"""

import json
import logging
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from pydantic import ValidationError

from .dbt import DbtExit
from .request import PlannedStep, RetryStep, parse_request, planned_step, step_spec
from .results import Counts, Outcome, StepResults, classify, read_results, summarise_nodes
from .store import Store, event_key, results_key, summary_key

log = logging.getLogger(__name__)


class RunError(Exception):
    """The run can't go ahead as requested."""


@dataclass(frozen=True)
class Config:
    run_id: str
    environment: str
    target: str
    project_dir: Path
    orcavault_ref: str
    orcavault_commit: str
    logs_url: str | None = None


class Dbt(Protocol):
    """What the runner needs from dbt.Dbt, so that tests can stand in for it."""

    stopping: bool

    def __call__(self, args: list[str]) -> DbtExit: ...


def plan(request_steps: list[PlannedStep], retry: str | None, store: Store) -> list[PlannedStep]:
    """The steps to run. A retry picks up an earlier run from its failed step."""
    if retry is None:
        return request_steps

    try:
        previous = store.get_json(summary_key(retry))
    except KeyError as e:
        raise RunError(f"Can't retry run {retry}: it has no summary at {e}") from e

    failed = next((step for step in previous["steps"] if not Outcome(step["outcome"]).ok), None)
    rest = [planned_step.validate_python(spec) for spec in previous["notRun"]]
    if failed is None:
        # A run that was stopped between steps has steps left, but none failed.
        if not rest:
            raise RunError(f"Can't retry run {retry}: it has nothing left to run")
        return rest
    if not failed["retryable"]:
        return [planned_step.validate_python(failed["spec"]), *rest]
    return [RetryStep(run=retry, step=failed["index"]), *rest]


def run_step(index: int, step: PlannedStep, config: Config, store: Store, dbt: Dbt) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "index": index,
        "spec": step_spec(step),
        "args": None,
        "exitCode": None,
        "outcome": Outcome.ERROR.value,
        "positionsAdvanced": None,
        "resultsKey": None,
        "retryable": False,
        "counts": Counts().to_json(),
        "failedNodes": [],
        "warnedNodes": [],
        "error": None,
    }

    results_path = config.project_dir / "target" / "run_results.json"
    # A stale file would be read as this step's results if dbt fails early.
    results_path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory() as state_dir:
        if isinstance(step, RetryStep):
            try:
                store.get_file(results_key(step.run, step.step), Path(state_dir) / "run_results.json")
            except KeyError as e:
                entry["error"] = f"No results to retry at {e}"
                log.error(entry["error"])
                return entry
            args = step.dbt_args(config.target, state_dir)
        else:
            args = step.dbt_args(config.target)

        entry["args"] = args
        dbt_exit = dbt(args)

    entry["exitCode"] = dbt_exit.code
    entry["positionsAdvanced"] = dbt_exit.positions_advanced

    results: StepResults | None = None
    if results_path.exists():
        run_results = json.loads(results_path.read_text())
        results = read_results(run_results)
        key = results_key(config.run_id, index)
        store.put_file(key, results_path)
        entry["resultsKey"] = key
        # Whether dbt retry can pick up where this step left off. Otherwise a
        # retry runs the step again whole. dbt retry reruns only the nodes in
        # run_results.json, and when dbt is interrupted it leaves out the ones it
        # hadn't started. It also refuses results without any nodes.
        entry["retryable"] = bool(run_results["results"]) and not dbt.stopping
        entry["counts"] = results.counts.to_json()
        entry["failedNodes"] = results.failed_nodes
        entry["warnedNodes"] = results.warned_nodes
    else:
        entry["error"] = "dbt wrote no run_results.json"

    outcome = classify(dbt_exit.code, results)
    entry["outcome"] = outcome.value
    log.info("Step %d %s: %s", index, step.command, outcome.value)
    return entry


def positions_advanced(steps: list[dict[str, Any]]) -> bool | None:
    reported = [step["positionsAdvanced"] for step in steps if step["positionsAdvanced"] is not None]
    return any(reported) if reported else None


def event_detail(summary: dict[str, Any], duration_minutes: int) -> dict[str, Any]:
    """The detail of the run's EventBridge event, less executionUrl, which the
    state machine adds. It's flat and already formatted, so that EventBridge
    input transformers can use it as it is."""
    counts = Counts()
    failed: list[str] = []
    warned: list[str] = []
    for step in summary["steps"]:
        counts += Counts.from_json(step["counts"])
        failed += step["failedNodes"]
        warned += step["warnedNodes"]

    return {
        "environment": summary["environment"],
        "outcome": summary["outcome"],
        "runId": summary["runId"],
        **counts.to_json(),
        "failedNodes": summarise_nodes(failed),
        "warnedNodes": summarise_nodes(warned),
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
        "steps": [],
        "notRun": [],
        "positionsAdvanced": None,
        "logsUrl": config.logs_url,
        "error": None,
        "event": None,
    }

    outcomes: list[Outcome] = []
    try:
        request = parse_request(raw_request)
        summary["request"] = request.model_dump(mode="json", exclude_defaults=True)
        steps = plan(list(request.steps), request.retry, store)
    except (ValidationError, RunError) as e:
        log.error("%s", e)
        summary["error"] = str(e)
        outcomes.append(Outcome.ERROR)
        steps = []

    for index, step in enumerate(steps):
        if dbt.stopping:
            summary["notRun"] = [step_spec(s) for s in steps[index:]]
            break
        entry = run_step(index, step, config, store, dbt)
        summary["steps"].append(entry)
        outcome = Outcome(entry["outcome"])
        outcomes.append(outcome)
        if not outcome.ok:
            summary["notRun"] = [step_spec(s) for s in steps[index + 1 :]]
            break

    if dbt.stopping:
        summary["error"] = "The run was stopped"
        outcomes.append(Outcome.ERROR)

    finished_at = datetime.now(timezone.utc)
    summary["outcome"] = Outcome.worst(outcomes).value
    summary["finishedAt"] = finished_at.isoformat()
    summary["positionsAdvanced"] = positions_advanced(summary["steps"])
    summary["event"] = event_detail(summary, round((finished_at - started_at).total_seconds() / 60))

    store.put_json(event_key(config.run_id), summary["event"])
    store.put_json(summary_key(config.run_id), summary)
    log.info("Run %s: %s, summary at %s", config.run_id, summary["outcome"], store.location(summary_key(config.run_id)))
    return summary
