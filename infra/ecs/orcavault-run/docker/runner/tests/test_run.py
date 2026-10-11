import json

import pytest
from fakes import FakeDbt, result, run_results

from orcavault_runner.results import Outcome
from orcavault_runner.run import one_line, run

HUB = "model.orcavault.hub_library"
LIMS = "model.orcavault.lims"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
ACCEPTED = "test.orcavault.accepted_values_lims_type.1c2d3e4f5a"
HOOK = "operation.orcavault.orcavault-on-run-end-0"


def test_scheduled_run(project_dir):
    dbt = FakeDbt(project_dir, results=[result(HUB, "success"), result(UNIQUE, "pass")])

    outcome, event = run("{}", project_dir, dbt)

    assert dbt.calls == [["build"]]
    assert outcome is Outcome.SUCCEEDED
    # As event.json has it.
    assert json.loads(event.model_dump_json()) == {
        "outcome": "succeeded",
        "error": None,
        "modelsSucceeded": 1,
        "modelsFailed": 0,
        "modelsSkipped": 0,
        "testsPassed": 1,
        "testsWarned": 0,
        "testsFailed": 0,
        "failedNodes": "",
        "warnedNodes": "",
    }


def test_failed_test(project_dir):
    dbt = FakeDbt(
        project_dir,
        code=1,
        results=[result(HUB, "success"), result(UNIQUE, "fail"), result(LIMS, "skipped"), result(ACCEPTED, "warn")],
    )

    outcome, event = run('{"args": "build --select +lims --fail-fast"}', project_dir, dbt)

    assert dbt.calls == [["build", "--select", "+lims", "--fail-fast"]]
    assert outcome is Outcome.TESTS_FAILED
    assert event.error is None
    assert event.failed_nodes == "unique_hub_library_library_hk"
    assert event.warned_nodes == "accepted_values_lims_type"
    assert event.models_skipped == 1


@pytest.mark.parametrize(
    "code, results, stop, mentions",
    [
        (1, [result(HUB, "success"), result(HOOK, "error")], False, "orcavault-on-run-end-0"),
        (2, [result(HUB, "success")], False, "2"),
        (2, None, False, "run_results.json"),
        (2, [result(HUB, "success")], True, "stopped"),
    ],
)
def test_errors(project_dir, code, results, stop, mentions):
    dbt = FakeDbt(project_dir, code=code, results=results, stop=stop)

    outcome, event = run("{}", project_dir, dbt)

    assert outcome is Outcome.ERROR
    # However it's worded, the error says what went wrong.
    assert mentions in event.error


@pytest.mark.parametrize(
    "request_json, stopping, mentions",
    [
        ('{"args": "run-operation drop_everything"}', False, "run-operation"),
        ("{}", True, "stopped"),
    ],
)
def test_runs_nothing(project_dir, request_json, stopping, mentions):
    dbt = FakeDbt(project_dir, stopping=stopping)

    outcome, event = run(request_json, project_dir, dbt)

    assert dbt.calls == []
    assert outcome is Outcome.ERROR
    assert mentions in event.error


def test_earlier_results_are_not_read_as_this_runs(project_dir):
    earlier = project_dir / "target" / "run_results.json"
    earlier.parent.mkdir()
    earlier.write_text(json.dumps(run_results(result(HUB, "success"))))

    _, event = run("{}", project_dir, FakeDbt(project_dir, code=2, results=None))

    assert event.models_succeeded == 0


def test_one_line():
    assert one_line('a "b"\\\n  c\x00', limit=10) == "a 'b' c"
    assert one_line("x" * 11, limit=10) == "xxxxxxx..."
