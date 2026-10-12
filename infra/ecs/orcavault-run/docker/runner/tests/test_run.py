import json
from pathlib import Path

import pytest
from fakes import FakeDbt, result, run_results

from orcavault_runner.results import Outcome
from orcavault_runner.run import one_line, run

HUB = "model.orcavault.hub_library"
LIMS = "model.orcavault.lims"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
ACCEPTED = "test.orcavault.accepted_values_lims_type.1c2d3e4f5a"
EPHEMERAL = "model.orcavault.int_cdc_mm_library_sample"


def test_scheduled_run():
    dbt = FakeDbt(results=[result(HUB, "success"), result(UNIQUE, "pass")])

    event = run("{}", dbt)

    assert dbt.calls == [("build",)]
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


def test_failed_test():
    dbt = FakeDbt(
        code=1,
        results=[result(HUB, "success"), result(UNIQUE, "fail"), result(LIMS, "skipped"), result(ACCEPTED, "warn")],
    )

    event = run('{"args": "build --select +lims --fail-fast"}', dbt)

    assert dbt.calls == [("build", "--select", "+lims", "--fail-fast")]
    assert event.outcome is Outcome.FAILED
    assert event.error is None
    assert event.failed_nodes == [UNIQUE]
    assert event.warned_nodes == [ACCEPTED]
    assert event.models_skipped == 1


@pytest.mark.parametrize(
    "code, results, stop, mentions",
    [
        (2, [result(HUB, "success")], False, "2"),
        (2, None, False, "run_results.json"),
        (2, [result(HUB, "success")], True, "stopped"),
        # An ephemeral model has no result, so a failed one is only in why dbt
        # skipped what depends on it.
        (1, [result(LIMS, "skipped"), result(HUB, "skipped", f"caused by {EPHEMERAL}")], False, EPHEMERAL),
    ],
)
def test_errors(code, results, stop, mentions):
    # Left by an earlier dbt command, such as one run by hand. It's not read as
    # this run's when dbt writes none.
    earlier = Path("target", "run_results.json")
    earlier.parent.mkdir()
    earlier.write_text(json.dumps(run_results(result(LIMS, "success"))))

    event = run("{}", FakeDbt(code=code, results=results, stop=stop))

    assert event.outcome is Outcome.ERROR
    # However it's worded, the error says what went wrong.
    assert mentions in event.error


def test_invalid_request():
    dbt = FakeDbt()

    event = run('{"args": "run-operation drop_everything"}', dbt)

    assert dbt.calls == []
    assert event.outcome is Outcome.ERROR
    assert "run-operation" in event.error


def test_one_line():
    assert one_line('a "b"\\\n  c\x00', limit=10) == "a 'b' c"
    assert one_line("x" * 11, limit=10) == "xxxxxxx..."
