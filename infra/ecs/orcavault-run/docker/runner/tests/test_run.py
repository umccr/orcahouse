import json
from dataclasses import replace

import pytest
from fakes import FakeDbt, Invocation, result

from orcavault_runner.run import run
from orcavault_runner.store import event_key, results_key, summary_key

HUB = "model.orcavault.hub_library"
LIMS = "model.orcavault.lims"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
ACCEPTED = "test.orcavault.accepted_values_lims_type.1c2d3e4f5a"

LIMS_BUILD = ["build", "--select", "+lims", "--fail-fast"]


def test_scheduled_run(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(HUB, "success"), result(UNIQUE, "pass")], positions_advanced=True),
    )

    summary = run("{}", config, store, dbt)

    assert dbt.calls == [["build"]]
    assert summary == store.get_json(summary_key("run-1"))
    assert summary["outcome"] == "succeeded"
    assert summary["error"] is None
    assert summary["request"] == {"args": ["build"]}
    assert summary["args"] == ["build"]
    assert summary["retryOf"] is None
    assert summary["exitCode"] == 0
    assert summary["positionsAdvanced"] is True
    assert summary["resultsKey"] == results_key("run-1")
    assert summary["retryable"]
    assert store.get_json(results_key("run-1"))["results"][0]["unique_id"] == HUB

    assert summary["event"] == {
        "environment": "prod",
        "outcome": "succeeded",
        "runId": "run-1",
        "modelsSucceeded": 1,
        "modelsFailed": 0,
        "modelsSkipped": 0,
        "testsPassed": 1,
        "testsWarned": 0,
        "testsFailed": 0,
        "failedNodes": "",
        "warnedNodes": "",
        "positionsAdvanced": True,
        "orcavaultRef": "v1.0.0",
        "durationMinutes": 0,
        "logsUrl": "https://logs",
    }
    assert store.get_json(event_key("run-1")) == summary["event"]


def test_args_go_to_dbt_as_they_are(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(results=[result(LIMS, "success")]))

    summary = run('{"args": "build --select +lims --fail-fast"}', config, store, dbt)

    assert dbt.calls == [LIMS_BUILD]
    assert summary["args"] == LIMS_BUILD
    assert summary["outcome"] == "succeeded"


def test_failed_test(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(
            code=1,
            results=[result(HUB, "success"), result(UNIQUE, "fail"), result(LIMS, "skipped"), result(ACCEPTED, "warn")],
            positions_advanced=False,
        ),
    )

    summary = run("{}", config, store, dbt)

    assert summary["outcome"] == "tests_failed"
    assert summary["exitCode"] == 1
    assert summary["positionsAdvanced"] is False
    assert summary["failedNodes"] == [UNIQUE]
    assert summary["warnedNodes"] == [ACCEPTED]
    assert summary["event"]["failedNodes"] == "unique_hub_library_library_hk"
    assert summary["event"]["warnedNodes"] == "accepted_values_lims_type"
    assert summary["event"]["modelsSkipped"] == 1


def test_invalid_request_runs_nothing(config, store, project_dir):
    dbt = FakeDbt(project_dir)

    summary = run('{"args": "run-operation drop_everything"}', config, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert "run-operation" in summary["error"]
    assert summary["request"] is None
    assert summary["args"] is None
    assert summary["event"]["outcome"] == "error"


def test_dbt_that_writes_no_results(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=None))

    summary = run("{}", config, store, dbt)

    assert summary["outcome"] == "error"
    assert summary["exitCode"] == 2
    assert summary["resultsKey"] is None
    assert summary["error"] == "dbt exited with 2 and wrote no run_results.json, see the logs"


def test_earlier_results_are_not_read_as_this_runs(config, store, project_dir):
    stale = project_dir / "target" / "run_results.json"
    stale.parent.mkdir()
    stale.write_text("{}")
    dbt = FakeDbt(project_dir, Invocation(code=2, results=None))

    summary = run("{}", config, store, dbt)

    assert summary["resultsKey"] is None
    assert summary["error"] == "dbt exited with 2 and wrote no run_results.json, see the logs"


def test_stopped_run(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=[result(HUB, "success")], stop=True))

    summary = run("{}", config, store, dbt)

    assert summary["outcome"] == "error"
    assert summary["error"] == "The run was stopped"
    assert summary["resultsKey"] == results_key("run-1")
    assert not summary["retryable"]


def test_stopped_before_dbt_starts(config, store, project_dir):
    dbt = FakeDbt(project_dir)
    dbt.stopping = True

    summary = run("{}", config, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert summary["error"] == "The run was stopped"


def failed_run(config, store, project_dir):
    """A run that failed a test."""
    dbt = FakeDbt(project_dir, Invocation(code=1, results=[result(HUB, "success"), result(UNIQUE, "fail")]))
    return run(json.dumps({"args": LIMS_BUILD}), config, store, dbt)


def test_retry_reruns_what_failed(config, store, project_dir):
    failed_run(config, store, project_dir)
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[result(UNIQUE, "pass")]))

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    [args] = dbt.calls
    assert args[:2] == ["retry", "--state"]
    assert dbt.state_files == [store.get_json(results_key("run-1"))]
    assert summary["outcome"] == "succeeded"
    assert summary["request"] == {"retry": "run-1"}
    assert summary["args"] == ["retry"]
    assert summary["retryOf"] == "run-1"
    assert summary["resultsKey"] == results_key("run-2")


def test_retry_a_retry(config, store, project_dir):
    failed_run(config, store, project_dir)
    second = replace(config, run_id="run-2")
    third = replace(config, run_id="run-3")
    run('{"retry": "run-1"}', second, store, FakeDbt(project_dir, Invocation(code=1, results=[result(UNIQUE, "fail")])))
    dbt = FakeDbt(project_dir, Invocation(results=[result(UNIQUE, "pass")]))

    summary = run('{"retry": "run-2"}', third, store, dbt)

    assert dbt.state_files == [store.get_json(results_key("run-2"))]
    assert summary["retryOf"] == "run-2"


def test_retry_reruns_a_run_without_results(config, store, project_dir):
    run(json.dumps({"args": LIMS_BUILD}), config, store, FakeDbt(project_dir, Invocation(code=2, results=None)))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[]))

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == [LIMS_BUILD]
    assert summary["args"] == LIMS_BUILD
    assert summary["retryOf"] is None
    assert summary["outcome"] == "succeeded"


@pytest.mark.parametrize(
    "invocation",
    [
        # dbt leaves the nodes it hadn't started out of run_results.json.
        Invocation(code=2, results=[result(HUB, "success")], stop=True),
        # dbt retry refuses results without any nodes.
        Invocation(code=2, results=[]),
    ],
)
def test_retry_reruns_a_run_that_dbt_retry_cant_pick_up(config, store, project_dir, invocation):
    first = run(json.dumps({"args": LIMS_BUILD}), config, store, FakeDbt(project_dir, invocation))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[]))

    run('{"retry": "run-1"}', retry, store, dbt)

    assert first["resultsKey"] is not None
    assert not first["retryable"]
    assert dbt.calls == [LIMS_BUILD]


def test_retry_a_stopped_retry(config, store, project_dir):
    failed_run(config, store, project_dir)
    second = replace(config, run_id="run-2")
    third = replace(config, run_id="run-3")
    run('{"retry": "run-1"}', second, store, FakeDbt(project_dir, Invocation(code=2, results=[], stop=True)))
    dbt = FakeDbt(project_dir, Invocation(results=[result(UNIQUE, "pass")]))

    summary = run('{"retry": "run-2"}', third, store, dbt)

    # The stopped retry is run again, from the first run's results.
    assert dbt.calls[0][:2] == ["retry", "--state"]
    assert dbt.state_files == [store.get_json(results_key("run-1"))]
    assert summary["retryOf"] == "run-1"


@pytest.mark.parametrize(
    "previous, error",
    [
        (None, "Can't retry run run-1: it has no summary"),
        ("{}", "Can't retry run run-1: it succeeded, so nothing failed"),
        ('{"args": "debug"}', "Can't retry run run-1: it didn't run dbt, because: args must start with"),
    ],
)
def test_nothing_to_retry(config, store, project_dir, previous, error):
    if previous is not None:
        run(previous, config, store, FakeDbt(project_dir, Invocation(results=[])))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir)

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert summary["error"].startswith(error)
    assert summary["request"] == {"retry": "run-1"}


def test_retry_with_missing_results(config, store, project_dir):
    failed_run(config, store, project_dir)
    (store.root / results_key("run-1")).unlink()
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir)

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert summary["error"].startswith("No results to retry")
    assert summary["retryOf"] == "run-1"
