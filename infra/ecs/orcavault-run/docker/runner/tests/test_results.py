import pytest
from mocks import result, run_results

from orcavault_runner.results import NODES_LISTED, Event, Outcome, classify, read_results

HUB = "model.orcavault.hub_library"
SAT = "model.orcavault.sat_library"
LIMS = "model.orcavault.lims"
SEED = "seed.orcavault.mdm__workflow_run"
NOT_NULL = "test.orcavault.not_null_hub_library_library_hk.4f2a9c1b0e"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
SINGULAR = "test.orcavault.assert_library_has_subject"
UNIT = "unit_test.orcavault.sat_library.test_sat_library_hash_diff"
ON_RUN_END = "operation.orcavault.orcavault-on-run-end-0"


def test_read_results():
    assert read_results(
        run_results(
            result(HUB, "success"),
            result(SEED, "success"),
            result(SAT, "error"),
            result(LIMS, "skipped"),
            result(NOT_NULL, "pass"),
            result(UNIQUE, "fail"),
            result(SINGULAR, "warn"),
            result(UNIT, "error"),
            result(ON_RUN_END, "error"),
        )
    ) == Event(
        models_succeeded=2,
        models_failed=1,
        models_skipped=1,
        tests_passed=1,
        tests_warned=1,
        tests_failed=2,
        failed_nodes=[SAT, UNIQUE, UNIT, ON_RUN_END],
        warned_nodes=[SINGULAR],
    )


@pytest.mark.parametrize(
    "exit_code, event, outcome",
    [
        (0, Event(), Outcome.SUCCEEDED),
        (0, Event(warned_nodes=[SINGULAR]), Outcome.WARNED),
        (1, Event(failed_nodes=[UNIQUE, ON_RUN_END], warned_nodes=[SINGULAR]), Outcome.FAILED),
        (1, Event(), Outcome.ERROR),
        (2, Event(failed_nodes=[SAT]), Outcome.ERROR),
    ],
)
def test_classify(exit_code, event, outcome):
    assert classify(exit_code, event) == outcome


def test_exit_codes():
    assert [outcome.exit_code for outcome in Outcome] == [0, 0, 1, 1, 1]


def test_nodes_summarised():
    assert Event(failed_nodes=[HUB, NOT_NULL, SINGULAR, UNIT, HUB]).model_dump()["failedNodes"] == (
        "hub_library, not_null_hub_library_library_hk, assert_library_has_subject, test_sat_library_hash_diff"
    )
    nodes = [f"model.orcavault.m{i}" for i in range(NODES_LISTED + 2)]
    assert Event(warned_nodes=nodes).model_dump()["warnedNodes"] == "m0, m1, m2, m3, m4, m5, m6, m7, m8, m9 and 2 more"
