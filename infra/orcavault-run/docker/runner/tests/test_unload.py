import json
from pathlib import Path

import pytest
from mocks import MockDbt, result, run_results

from orcavault_runner.results import Outcome, UnloadOutcome
from orcavault_runner.unload import Unload, UnloadError, run_unload

CALL = "macro.orcavault.run_unload_schema"

ENVIRONMENT = {
    "schema": "mart",
    "s3_path": "s3://orcavault-dev-warehouse-123456789012-ap-southeast-2-an/v1",
    "iam_role_arn": "arn:aws:iam::123456789012:role/dev-redshift-namespace-role",
}
CALL_ARGS = {
    "schema_name": "mart",
    "s3_bucket_path": "s3://orcavault-dev-warehouse-123456789012-ap-southeast-2-an/v1",
    "iam_role_arn": "arn:aws:iam::123456789012:role/dev-redshift-namespace-role",
}


def write_target(name: str, content: str) -> None:
    path = Path("target", name)
    path.parent.mkdir(exist_ok=True)
    path.write_text(content)


def test_unload():
    dbt = MockDbt(results=[result(CALL, "success")])

    event = run_unload(dbt, **ENVIRONMENT)

    assert dbt.calls == [("run-operation", "run_unload_schema", "--args", json.dumps(CALL_ARGS))]
    assert event.outcome is Outcome.SUCCEEDED
    assert event.unload_outcome is UnloadOutcome.SUCCEEDED
    assert event.error is None
    assert json.loads(event.model_dump_json())["unloadOutcome"] == "succeeded"


def test_failed_call():
    dbt = MockDbt(code=1, results=[result(CALL, "error")])

    event = run_unload(dbt, **ENVIRONMENT)

    assert event.outcome is Outcome.FAILED
    assert event.unload_outcome is UnloadOutcome.FAILED
    assert event.model_dump()["failedNodes"] == "run_unload_schema"
    assert event.error is None


def test_call_without_results():
    """A call that writes no results isn't read from a result already in target."""
    write_target("run_results.json", json.dumps(run_results(result(CALL, "success"))))
    dbt = MockDbt(code=2, results=None)

    event = run_unload(dbt, **ENVIRONMENT)

    assert event.outcome is Outcome.ERROR
    assert event.unload_outcome is UnloadOutcome.FAILED
    assert event.error is not None
    assert "run_results.json" in event.error


def test_stopped():
    dbt = MockDbt(results=[result(CALL, "success")], stop=True)

    event = run_unload(dbt, **ENVIRONMENT)

    assert event.outcome is Outcome.ERROR
    assert event.unload_outcome is UnloadOutcome.FAILED
    assert event.error == "The run was stopped"


def test_artifacts_cleared():
    """The image's manifest and an earlier result aren't kept as the step's."""
    write_target("manifest.json", "{}")
    write_target("run_results.json", json.dumps(run_results()))

    run_unload(MockDbt(), **{**ENVIRONMENT, "schema": None})

    assert not Path("target", "manifest.json").exists()
    assert not Path("target", "run_results.json").exists()


@pytest.mark.parametrize(
    "environment, mentions",
    [
        ({"schema": None, "s3_path": ""}, "set ORCAVAULT_UNLOAD_SCHEMA, ORCAVAULT_UNLOAD_S3_PATH"),
        ({"schema": "Mart"}, "ORCAVAULT_UNLOAD_SCHEMA"),
        # The procedure adds the slash after the path.
        ({"s3_path": "s3://bucket/v1/"}, "ORCAVAULT_UNLOAD_S3_PATH"),
        ({"s3_path": "s3://bucket/v1' --"}, "ORCAVAULT_UNLOAD_S3_PATH"),
        ({"s3_path": "bucket/v1"}, "ORCAVAULT_UNLOAD_S3_PATH"),
        ({"iam_role_arn": "default"}, "ORCAVAULT_UNLOAD_IAM_ROLE_ARN"),
    ],
)
def test_invalid_environment(environment, mentions):
    dbt = MockDbt()

    event = run_unload(dbt, **{**ENVIRONMENT, **environment})

    assert dbt.calls == []
    assert event.outcome is Outcome.ERROR
    assert event.unload_outcome is UnloadOutcome.FAILED
    assert event.error is not None
    assert mentions in event.error


def test_s3_path_needs_a_bucket():
    with pytest.raises(UnloadError):
        Unload.from_environment(**{**ENVIRONMENT, "s3_path": "s3://"})
