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

BUILD = ["build", "--target", "prod", "--exclude-resource-type", "unit_test"]


def test_scheduled_run(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(HUB, "success"), result(UNIQUE, "pass")], positions_advanced=True),
    )

    summary = run("{}", config, store, dbt)

    assert dbt.calls == [BUILD]
    assert summary == store.get_json(summary_key("run-1"))
    assert summary["outcome"] == "succeeded"
    assert summary["error"] is None
    assert summary["notRun"] == []
    assert summary["positionsAdvanced"] is True
    assert summary["request"] == {"steps": [{}]}

    [step] = summary["steps"]
    assert step["spec"] == {"command": "build"}
    assert step["exitCode"] == 0
    assert step["resultsKey"] == results_key("run-1", 0)
    assert step["retryable"]
    assert store.get_json(results_key("run-1", 0))["results"][0]["unique_id"] == HUB

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


def test_failed_test_stops_later_steps(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(
            code=1,
            results=[result(HUB, "success"), result(UNIQUE, "fail"), result(LIMS, "skipped"), result(ACCEPTED, "warn")],
            positions_advanced=False,
        ),
    )

    summary = run('{"steps": [{"select": "+lims"}, {"command": "seed"}]}', config, store, dbt)

    assert len(dbt.calls) == 1
    assert summary["outcome"] == "tests_failed"
    assert summary["notRun"] == [{"command": "seed"}]
    assert summary["positionsAdvanced"] is False
    assert summary["event"]["failedNodes"] == "unique_hub_library_library_hk"
    assert summary["event"]["warnedNodes"] == "accepted_values_lims_type"
    assert summary["event"]["modelsSkipped"] == 1


def test_counts_add_up_across_steps(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(HUB, "success")]),
        Invocation(results=[result(LIMS, "success"), result(ACCEPTED, "warn")]),
    )

    summary = run('{"steps": [{"select": "hub_library"}, {"select": "lims"}]}', config, store, dbt)

    assert summary["outcome"] == "warned"
    assert summary["event"]["modelsSucceeded"] == 2
    assert summary["event"]["testsWarned"] == 1
    assert summary["positionsAdvanced"] is None


def test_invalid_request_runs_nothing(config, store, project_dir):
    dbt = FakeDbt(project_dir)

    summary = run('{"selct": "lims"}', config, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert "selct" in summary["error"]
    assert summary["request"] is None
    assert summary["event"]["outcome"] == "error"


def test_dbt_that_writes_no_results(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=None))

    summary = run("{}", config, store, dbt)

    [step] = summary["steps"]
    assert summary["outcome"] == "error"
    assert step["resultsKey"] is None
    assert step["error"] == "dbt wrote no run_results.json"


def test_an_earlier_steps_results_are_not_reused(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(HUB, "success")]),
        Invocation(code=2, results=None),
    )

    summary = run('{"steps": [{}, {}]}', config, store, dbt)

    assert summary["steps"][1]["outcome"] == "error"
    assert summary["steps"][1]["resultsKey"] is None


def test_stopped_run(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=0, results=[result(HUB, "success")], stop=True))

    summary = run('{"steps": [{}, {"command": "seed"}]}', config, store, dbt)

    assert len(dbt.calls) == 1
    assert summary["outcome"] == "error"
    assert summary["error"] == "The run was stopped"
    assert summary["notRun"] == [{"command": "seed"}]


def failed_run(config, store, project_dir):
    """A run whose first of three steps failed a test."""
    dbt = FakeDbt(project_dir, Invocation(code=1, results=[result(HUB, "success"), result(UNIQUE, "fail")]))
    request = {"steps": [{"select": "+lims", "fail_fast": True}, {"command": "seed"}, {"command": "test"}]}
    return run(json.dumps(request), config, store, dbt)


def test_retry_reruns_what_failed_then_the_rest(config, store, project_dir):
    failed_run(config, store, project_dir)
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(UNIQUE, "pass")]),
        Invocation(results=[]),
        Invocation(results=[]),
    )

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls[0][:4] == ["retry", "--target", "prod", "--state"]
    assert dbt.state_files[0] == store.get_json(results_key("run-1", 0))
    assert dbt.calls[1:] == [["seed", "--target", "prod"], ["test", "--target", "prod", "--exclude-resource-type", "unit_test"]]
    assert summary["outcome"] == "succeeded"
    assert summary["request"] == {"retry": "run-1"}
    assert [step["spec"] for step in summary["steps"]] == [
        {"command": "retry", "run": "run-1", "step": 0},
        {"command": "seed"},
        {"command": "test"},
    ]


def test_retry_a_retry(config, store, project_dir):
    failed_run(config, store, project_dir)
    second = replace(config, run_id="run-2")
    third = replace(config, run_id="run-3")
    run('{"retry": "run-1"}', second, store, FakeDbt(project_dir, Invocation(code=1, results=[result(UNIQUE, "fail")])))
    dbt = FakeDbt(project_dir, Invocation(results=[]), Invocation(results=[]), Invocation(results=[]))

    summary = run('{"retry": "run-2"}', third, store, dbt)

    assert dbt.state_files[0] == store.get_json(results_key("run-2", 0))
    assert summary["steps"][0]["spec"] == {"command": "retry", "run": "run-2", "step": 0}
    assert len(dbt.calls) == 3


def test_retry_reruns_a_step_without_results(config, store, project_dir):
    run('{"select": "+lims"}', config, store, FakeDbt(project_dir, Invocation(code=2, results=None)))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[]))

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == [[*BUILD, "--select", "+lims"]]
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
def test_retry_reruns_a_step_that_dbt_retry_cant_pick_up(config, store, project_dir, invocation):
    first = run('{"steps": [{"select": "+lims"}, {"command": "seed"}]}', config, store, FakeDbt(project_dir, invocation))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[]), Invocation(results=[]))

    run('{"retry": "run-1"}', retry, store, dbt)

    assert first["steps"][0]["resultsKey"] is not None
    assert not first["steps"][0]["retryable"]
    assert dbt.calls == [[*BUILD, "--select", "+lims"], ["seed", "--target", "prod"]]


def test_retry_a_stopped_run(config, store, project_dir):
    run('{"steps": [{}, {"command": "seed"}]}', config, store, FakeDbt(project_dir, Invocation(results=[], stop=True)))
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir, Invocation(results=[]))

    run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == [["seed", "--target", "prod"]]


@pytest.mark.parametrize(
    "previous, error",
    [
        (None, "Can't retry run run-1: it has no summary"),
        ("{}", "Can't retry run run-1: it has nothing left to run"),
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


def test_retry_with_missing_results(config, store, project_dir):
    failed_run(config, store, project_dir)
    (store.root / results_key("run-1", 0)).unlink()
    retry = replace(config, run_id="run-2")
    dbt = FakeDbt(project_dir)

    summary = run('{"retry": "run-1"}', retry, store, dbt)

    assert dbt.calls == []
    assert summary["outcome"] == "error"
    assert summary["steps"][0]["error"].startswith("No results to retry")
    assert summary["notRun"] == [{"command": "seed"}, {"command": "test"}]
