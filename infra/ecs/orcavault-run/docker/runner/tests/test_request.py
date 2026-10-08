import pytest
from pydantic import ValidationError

from orcavault_runner.request import MAX_STEPS, RetryStep, Step, parse_request, planned_step, step_spec

DEFAULT_ARGS = ["build", "--target", "prod", "--exclude-resource-type", "unit_test"]


@pytest.mark.parametrize("raw", ["", "  ", "{}"])
def test_empty_request_builds_everything(raw):
    request = parse_request(raw)

    assert request.steps == (Step(),)
    assert request.steps[0].dbt_args("prod") == DEFAULT_ARGS


def test_top_level_fields_are_one_step():
    request = parse_request('{"select": "+lims  fastq", "fail_fast": true}')

    assert request.steps == (Step(select=("+lims", "fastq"), fail_fast=True),)


def test_steps_run_in_order():
    request = parse_request('{"steps": [{"command": "seed"}, {"select": ["mart"]}]}')

    assert [step.command for step in request.steps] == ["seed", "build"]
    assert request.steps[1].select == ("mart",)


def test_all_flags():
    step = Step(
        command="build",
        select="+lims",
        exclude=["legacy", "resource_type:test"],
        indirect_selection="cautious",
        fail_fast=True,
        full_refresh=True,
        vars={"cdc_position_margin_minutes": 30},
    )

    assert step.dbt_args("prod") == [
        *DEFAULT_ARGS,
        "--select",
        "+lims",
        "--exclude",
        "legacy",
        "resource_type:test",
        "--indirect-selection",
        "cautious",
        "--fail-fast",
        "--full-refresh",
        "--vars",
        '{"cdc_position_margin_minutes": 30}',
    ]


def test_selector():
    assert Step(selector="marts").dbt_args("prod") == [*DEFAULT_ARGS, "--selector", "marts"]


@pytest.mark.parametrize("command", ["run", "seed", "snapshot"])
def test_unit_tests_are_only_excluded_where_dbt_runs_tests(command):
    assert Step(command=command).dbt_args("prod") == [command, "--target", "prod"]


@pytest.mark.parametrize(
    "raw, message",
    [
        ('{"selct": "lims"}', "Extra inputs are not permitted"),
        ('{"command": "run-operation"}', "Input should be"),
        ('{"selector": "marts", "select": "lims"}', "selector can't be combined"),
        ('{"command": "test", "full_refresh": true}', "full_refresh doesn't apply to test"),
        ('{"command": "run", "indirect_selection": "cautious"}', "indirect_selection doesn't apply to run"),
        ('{"steps": []}', "either steps or retry"),
        ('{"steps": [{}], "retry": "run-1"}', "either steps or retry"),
        ('{"retry": "../run-1"}', "should match pattern"),
        ('{"steps": [' + ", ".join(["{}"] * (MAX_STEPS + 1)) + "]}", "at most 10 items"),
        ("[]", "Input should be"),
        ("not json", "Invalid JSON"),
    ],
)
def test_invalid_requests(raw, message):
    with pytest.raises(ValidationError, match=message):
        parse_request(raw)


def test_retry_request():
    request = parse_request('{"retry": "run-1"}')

    assert request.retry == "run-1"
    assert request.steps == ()


def test_retry_step_args():
    step = RetryStep(run="run-1", step=0)

    assert step.dbt_args("prod", "/tmp/state") == ["retry", "--target", "prod", "--state", "/tmp/state"]


@pytest.mark.parametrize(
    "step, spec",
    [
        (Step(), {"command": "build"}),
        (Step(command="seed", full_refresh=True), {"command": "seed", "full_refresh": True}),
        (Step(select="+lims", vars={"a": 1}), {"command": "build", "select": ["+lims"], "vars": {"a": 1}}),
        (RetryStep(run="run-1", step=2), {"command": "retry", "run": "run-1", "step": 2}),
    ],
)
def test_specs_round_trip(step, spec):
    assert step_spec(step) == spec
    assert planned_step.validate_python(spec) == step
