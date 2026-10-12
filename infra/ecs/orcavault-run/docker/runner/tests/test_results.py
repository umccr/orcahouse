import pytest
from fakes import result, run_results

from orcavault_runner.results import Counts, Outcome, RunResults, classify, read_results, summarise_nodes

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
    results = read_results(
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
    )

    assert results.counts == Counts(
        models_succeeded=2,
        models_failed=1,
        models_skipped=1,
        tests_passed=1,
        tests_warned=1,
        tests_failed=2,
    )
    assert results.failed_nodes == [SAT, UNIQUE, UNIT, ON_RUN_END]
    assert results.warned_nodes == [SINGULAR]


@pytest.mark.parametrize(
    "exit_code, results, outcome",
    [
        (0, RunResults(), Outcome.SUCCEEDED),
        (0, RunResults(warned_nodes=[SINGULAR]), Outcome.WARNED),
        (1, RunResults(failed_nodes=[UNIQUE, ON_RUN_END], warned_nodes=[SINGULAR]), Outcome.FAILED),
        # dbt failed without a node failing.
        (1, RunResults(), Outcome.ERROR),
        (2, RunResults(failed_nodes=[SAT]), Outcome.ERROR),
        (1, None, Outcome.ERROR),
    ],
)
def test_classify(exit_code, results, outcome):
    assert classify(exit_code, results) == outcome


def test_exit_codes():
    assert [outcome.exit_code for outcome in Outcome] == [0, 0, 1, 1, 2]


def test_summarise_nodes():
    # By the names people know them by, once each.
    assert summarise_nodes([HUB, NOT_NULL, SINGULAR, UNIT, HUB]) == (
        "hub_library, not_null_hub_library_library_hk, assert_library_has_subject, test_sat_library_hash_diff"
    )
    assert summarise_nodes([f"model.orcavault.m{i}" for i in range(12)]) == (
        "m0, m1, m2, m3, m4, m5, m6, m7, m8, m9 and 2 more"
    )
