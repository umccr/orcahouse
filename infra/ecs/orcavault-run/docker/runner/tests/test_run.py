import json
from typing import Any

import pytest
from fakes import FakeDbt, Invocation, result

from orcavault_runner.results import Outcome
from orcavault_runner.run import one_line, run
from orcavault_runner.store import DirStore, event_key

HUB = "model.orcavault.hub_library"
LIMS = "model.orcavault.lims"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
ACCEPTED = "test.orcavault.accepted_values_lims_type.1c2d3e4f5a"
HOOK = "operation.orcavault.orcavault-on-run-end-0"

LIMS_BUILD = ["build", "--select", "+lims", "--fail-fast"]


def read_event(store: DirStore) -> dict[str, Any]:
    return json.loads((store.root / event_key("run-1")).read_text())


def test_scheduled_run(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(results=[result(HUB, "success"), result(UNIQUE, "pass")], positions_advanced=True),
    )

    outcome = run("{}", config, store, dbt)

    assert dbt.calls == [["build"]]
    assert outcome is Outcome.SUCCEEDED
    assert read_event(store) == {
        "environment": "prod",
        "outcome": "succeeded",
        "error": None,
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


def test_args_go_to_dbt_as_they_are(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(results=[result(LIMS, "success")]))

    outcome = run('{"args": "build --select +lims --fail-fast"}', config, store, dbt)

    assert dbt.calls == [LIMS_BUILD]
    assert outcome is Outcome.SUCCEEDED


def test_failed_test(config, store, project_dir):
    dbt = FakeDbt(
        project_dir,
        Invocation(
            code=1,
            results=[result(HUB, "success"), result(UNIQUE, "fail"), result(LIMS, "skipped"), result(ACCEPTED, "warn")],
            positions_advanced=False,
        ),
    )

    outcome = run("{}", config, store, dbt)

    event = read_event(store)
    assert outcome is Outcome.TESTS_FAILED
    assert event["outcome"] == "tests_failed"
    assert event["error"] is None
    assert event["positionsAdvanced"] is False
    assert event["failedNodes"] == "unique_hub_library_library_hk"
    assert event["warnedNodes"] == "accepted_values_lims_type"
    assert event["modelsSkipped"] == 1


def test_failed_hook(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=1, results=[result(HUB, "success"), result(HOOK, "error")]))

    run("{}", config, store, dbt)

    event = read_event(store)
    assert event["outcome"] == "error"
    assert event["error"] == "A hook failed: orcavault-on-run-end-0"
    assert event["failedNodes"] == "orcavault-on-run-end-0"


def test_dbt_that_fails_after_writing_results(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=[result(HUB, "success")]))

    run("{}", config, store, dbt)

    event = read_event(store)
    assert event["outcome"] == "error"
    assert event["error"] == "dbt exited with 2, see the logs"
    assert event["modelsSucceeded"] == 1


def test_invalid_request_runs_nothing(config, store, project_dir):
    dbt = FakeDbt(project_dir)

    outcome = run('{"args": "run-operation drop_everything"}', config, store, dbt)

    event = read_event(store)
    assert dbt.calls == []
    assert outcome is Outcome.ERROR
    assert event["outcome"] == "error"
    assert event["error"] == "args must start with one of build, run, test, seed, snapshot, not 'run-operation'"


def test_error_is_one_line(config, store, project_dir):
    run(json.dumps({'say "hi"\\\nthere': 1}), config, store, FakeDbt(project_dir))

    assert read_event(store)["error"] == "Unknown field say 'hi' there. A request only has args"


@pytest.mark.parametrize(
    "text, line",
    [
        ('a "b"', "a 'b'"),
        ("a\\b", "ab"),
        ("a\n  b\tc\r\n", "a b c"),
        ("a\x00b", "ab"),
        ("x" * 10, "x" * 10),
        ("x" * 11, "x" * 7 + "..."),
    ],
)
def test_one_line(text, line):
    assert one_line(text, limit=10) == line


def test_dbt_that_writes_no_results(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=None))

    run("{}", config, store, dbt)

    event = read_event(store)
    assert event["outcome"] == "error"
    assert event["error"] == "dbt exited with 2 and wrote no run_results.json, see the logs"


def test_earlier_results_are_not_read_as_this_runs(config, store, project_dir):
    stale = project_dir / "target" / "run_results.json"
    stale.parent.mkdir()
    stale.write_text(json.dumps({"results": [result(HUB, "success")]}))
    dbt = FakeDbt(project_dir, Invocation(code=2, results=None))

    run("{}", config, store, dbt)

    event = read_event(store)
    assert event["modelsSucceeded"] == 0
    assert event["error"] == "dbt exited with 2 and wrote no run_results.json, see the logs"


def test_stopped_run(config, store, project_dir):
    dbt = FakeDbt(project_dir, Invocation(code=2, results=[result(HUB, "success")], stop=True))

    outcome = run("{}", config, store, dbt)

    event = read_event(store)
    assert outcome is Outcome.ERROR
    assert event["error"] == "The run was stopped"
    assert event["modelsSucceeded"] == 1


def test_stopped_before_dbt_starts(config, store, project_dir):
    dbt = FakeDbt(project_dir)
    dbt.stopping = True

    run("{}", config, store, dbt)

    event = read_event(store)
    assert dbt.calls == []
    assert event["outcome"] == "error"
    assert event["error"] == "The run was stopped"
