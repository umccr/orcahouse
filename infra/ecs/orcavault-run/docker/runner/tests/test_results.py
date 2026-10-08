import pytest
from fakes import result, run_results

from orcavault_runner.results import Counts, Outcome, StepResults, classify, node_name, read_results, summarise_nodes

HUB = "model.orcavault.hub_library"
SAT = "model.orcavault.sat_library"
LIMS = "model.orcavault.lims"
SEED = "seed.orcavault.mdm__workflow_run"
NOT_NULL = "test.orcavault.not_null_hub_library_library_hk.4f2a9c1b0e"
UNIQUE = "test.orcavault.unique_hub_library_library_hk.9b8e7d6c5a"
SINGULAR = "test.orcavault.assert_library_has_subject"
UNIT = "unit_test.orcavault.sat_library.test_sat_library_hash_diff"
ON_RUN_END = "operation.orcavault.orcavault-on-run-end-0"


def test_counts_by_status():
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
            result(ON_RUN_END, "success"),
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
    assert results.failed_nodes == [SAT, UNIQUE, UNIT]
    assert results.warned_nodes == [SINGULAR]
    assert not results.hook_failed


def test_failed_hook():
    results = read_results(run_results(result(HUB, "success"), result(ON_RUN_END, "error")))

    assert results.hook_failed
    assert results.failed_nodes == [ON_RUN_END]


def test_partial_microbatch_counts_as_failed():
    assert read_results(run_results(result(HUB, "partial success"))).counts.models_failed == 1


def step_results(**counts: int) -> StepResults:
    return StepResults(counts=Counts(**counts))


@pytest.mark.parametrize(
    "exit_code, results, outcome",
    [
        (0, step_results(models_succeeded=3, tests_passed=4), Outcome.SUCCEEDED),
        (0, step_results(), Outcome.SUCCEEDED),
        (0, step_results(models_succeeded=3, tests_warned=1), Outcome.WARNED),
        (1, step_results(models_succeeded=3, tests_failed=1, models_skipped=1), Outcome.TESTS_FAILED),
        (1, step_results(models_failed=1, tests_failed=1), Outcome.MODELS_FAILED),
        (1, step_results(models_succeeded=3), Outcome.ERROR),
        (0, StepResults(hook_failed=True), Outcome.ERROR),
        (2, step_results(models_succeeded=3), Outcome.ERROR),
        (1, None, Outcome.ERROR),
        (-9, None, Outcome.ERROR),
    ],
)
def test_classify(exit_code, results, outcome):
    assert classify(exit_code, results) == outcome


def test_outcomes_from_best_to_worst():
    assert Outcome.worst([]) == Outcome.SUCCEEDED
    assert Outcome.worst([Outcome.WARNED, Outcome.SUCCEEDED]) == Outcome.WARNED
    assert Outcome.worst([Outcome.TESTS_FAILED, Outcome.MODELS_FAILED, Outcome.WARNED]) == Outcome.MODELS_FAILED
    assert Outcome.worst([Outcome.ERROR, Outcome.MODELS_FAILED]) == Outcome.ERROR


@pytest.mark.parametrize(
    "outcome, code",
    [
        (Outcome.SUCCEEDED, 0),
        (Outcome.WARNED, 0),
        (Outcome.TESTS_FAILED, 1),
        (Outcome.MODELS_FAILED, 1),
        (Outcome.ERROR, 2),
    ],
)
def test_exit_codes(outcome, code):
    assert outcome.exit_code == code


@pytest.mark.parametrize(
    "unique_id, name",
    [
        (HUB, "hub_library"),
        (SEED, "mdm__workflow_run"),
        (NOT_NULL, "not_null_hub_library_library_hk"),
        (SINGULAR, "assert_library_has_subject"),
        (UNIT, "test_sat_library_hash_diff"),
        (ON_RUN_END, "orcavault-on-run-end-0"),
    ],
)
def test_node_name(unique_id, name):
    assert node_name(unique_id) == name


def test_summarise_nodes():
    models = [f"model.orcavault.m{i}" for i in range(12)]

    assert summarise_nodes([]) == ""
    assert summarise_nodes([HUB, SAT]) == "hub_library, sat_library"
    assert summarise_nodes([HUB, HUB]) == "hub_library"
    assert summarise_nodes(models) == "m0, m1, m2, m3, m4, m5, m6, m7, m8, m9 and 2 more"
