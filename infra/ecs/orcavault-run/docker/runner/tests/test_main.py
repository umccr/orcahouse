import json
import os
import re
from pathlib import Path

import boto3
import pytest
from botocore.stub import Stubber

from orcavault_runner.__main__ import Settings, console_logs_url, ecs_logs_url, write_event
from orcavault_runner.run import Event


@pytest.fixture(autouse=True)
def unset_environment(monkeypatch):
    """Settings reads the process's environment, so without this a variable set
    in the shell, such as from running the image by hand, would reach the tests.
    Settings matches names in any case, and so does this."""
    for name in list(os.environ):
        if name.upper().startswith("ORCAVAULT_") or name.upper() == "ECS_CONTAINER_METADATA_URI_V4":
            monkeypatch.delenv(name)


LOGS_URL = (
    "https://ap-southeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-southeast-2"
    "#logsV2:log-groups/log-group/$252Faws$252Fecs$252Forcavault-run-dbt"
    "/log-events/dbt$252Fdbt$252F0123456789abcdef"
)


def test_console_logs_url():
    assert console_logs_url("ap-southeast-2", "/aws/ecs/orcavault-run-dbt", "dbt/dbt/0123456789abcdef") == LOGS_URL


def test_ecs_logs_url(tmp_path):
    metadata = tmp_path / "metadata.json"
    metadata.write_text(
        json.dumps(
            {
                "Name": "dbt",
                "LogDriver": "awslogs",
                "LogOptions": {
                    "awslogs-group": "/aws/ecs/orcavault-run-dbt",
                    "awslogs-region": "ap-southeast-2",
                    "awslogs-stream": "dbt/dbt/0123456789abcdef",
                },
            }
        )
    )

    assert ecs_logs_url(metadata.as_uri()) == LOGS_URL


@pytest.mark.parametrize("content", [None, "{}", "not json"])
def test_no_ecs_logs_url(tmp_path, content):
    metadata = tmp_path / "metadata.json"
    if content is not None:
        metadata.write_text(content)

    assert ecs_logs_url(metadata.as_uri()) is None
    assert ecs_logs_url(None) is None


# As ECS and the state machine set it.
ENVIRONMENT = {
    "ORCAVAULT_RUN_REQUEST": '{"args": "build"}',
    "ORCAVAULT_RUN_ID": "scheduled-2026-10-08",
    "ORCAVAULT_RESULTS_BUCKET": "bucket",
    "ORCAVAULT_RESULTS_DIR": "/events",
    "ORCAVAULT_ENVIRONMENT": "prod",
    "ORCAVAULT_REF": "v1.0.0",
    "ECS_CONTAINER_METADATA_URI_V4": "http://169.254.170.2/v4/0123456789abcdef",
}


def test_settings(monkeypatch):
    for name, value in ENVIRONMENT.items():
        monkeypatch.setenv(name, value)
    # dbt's, not the runner's.
    monkeypatch.setenv("ORCAVAULT_REDSHIFT_HOST", "localhost")
    monkeypatch.setenv("ORCAVAULT_DBT_THREADS", "4")

    assert Settings().model_dump() == {
        "run_request": '{"args": "build"}',
        "run_id": "scheduled-2026-10-08",
        "results_bucket": "bucket",
        "results_dir": Path("/events"),
        "environment": "prod",
        "ref": "v1.0.0",
        "ecs_metadata_uri": "http://169.254.170.2/v4/0123456789abcdef",
    }


@pytest.mark.parametrize("empty", [False, True])
def test_default_settings(monkeypatch, empty):
    if empty:
        for name in ENVIRONMENT:
            monkeypatch.setenv(name, "")

    settings = Settings()

    assert re.fullmatch(r"manual-\d{8}T\d{6}Z", settings.run_id)
    assert settings.model_dump(exclude={"run_id"}) == {
        "run_request": "",
        "results_bucket": None,
        "results_dir": None,
        "environment": "local",
        "ref": "unknown",
        "ecs_metadata_uri": None,
    }


EVENT = Event(environment="prod", run_id="run-1", orcavault_ref="v1.0.0")
EVENT_JSON = EVENT.model_dump_json(indent=2)


def test_write_event_to_s3(tmp_path, monkeypatch):
    client = boto3.client("s3", region_name="ap-southeast-2", aws_access_key_id="x", aws_secret_access_key="x")
    monkeypatch.setattr(boto3, "client", lambda service: client)
    with Stubber(client) as stubber:
        stubber.add_response(
            "put_object",
            {},
            {
                "Bucket": "bucket",
                "Key": "runs/run-1/event.json",
                "Body": EVENT_JSON.encode(),
                "ContentType": "application/json",
            },
        )

        location = write_event(EVENT, Settings(results_bucket="bucket"), tmp_path)

        stubber.assert_no_pending_responses()
    assert location == "s3://bucket/runs/run-1/event.json"


def test_write_event_to_a_directory(tmp_path):
    path = tmp_path / "target" / "runs" / "run-1" / "event.json"
    assert write_event(EVENT, Settings(), tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON

    path = tmp_path / "events" / "run-1" / "event.json"
    assert write_event(EVENT, Settings(results_dir=tmp_path / "events"), tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON
