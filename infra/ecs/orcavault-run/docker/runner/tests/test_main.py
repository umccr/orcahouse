import os
import re
from pathlib import Path

import boto3
import pytest
from botocore.stub import Stubber

from orcavault_runner.__main__ import Settings, write_event
from orcavault_runner.run import Event


@pytest.fixture(autouse=True)
def unset_environment(monkeypatch):
    """Settings reads the process's environment, so without this a variable set
    in the shell, such as from running the image by hand, would reach the tests.
    Settings matches names in any case, and so does this."""
    for name in list(os.environ):
        if name.upper().startswith("ORCAVAULT_"):
            monkeypatch.delenv(name)


# As ECS and the state machine set it.
ENVIRONMENT = {
    "ORCAVAULT_RUN_REQUEST": '{"args": "build"}',
    "ORCAVAULT_RUN_ID": "scheduled-2026-10-08",
    "ORCAVAULT_RESULTS_BUCKET": "bucket",
    "ORCAVAULT_RESULTS_DIR": "/events",
    "ORCAVAULT_REF": "v1.0.0",
}


def test_settings(monkeypatch):
    for name, value in ENVIRONMENT.items():
        monkeypatch.setenv(name, value)
    # dbt's, not the runner's.
    monkeypatch.setenv("ORCAVAULT_REDSHIFT_HOST", "localhost")

    assert Settings().model_dump() == {
        "run_request": '{"args": "build"}',
        "run_id": "scheduled-2026-10-08",
        "results_bucket": "bucket",
        "results_dir": Path("/events"),
        "ref": "v1.0.0",
    }


def test_empty_settings_are_defaults(monkeypatch):
    for name in ENVIRONMENT:
        monkeypatch.setenv(name, "")

    settings = Settings()

    assert re.fullmatch(r"manual-\d{8}T\d{6}Z", settings.run_id)
    assert settings.model_dump(exclude={"run_id"}) == {
        "run_request": "",
        "results_bucket": None,
        "results_dir": None,
        "ref": "unknown",
    }


EVENT = Event()
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

        location = write_event(EVENT, Settings(run_id="run-1", results_bucket="bucket"), tmp_path)

        stubber.assert_no_pending_responses()
    assert location == "s3://bucket/runs/run-1/event.json"


def test_write_event_to_a_directory(tmp_path):
    path = tmp_path / "target" / "runs" / "run-1" / "event.json"
    assert write_event(EVENT, Settings(run_id="run-1"), tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON

    path = tmp_path / "events" / "run-1" / "event.json"
    assert write_event(EVENT, Settings(run_id="run-1", results_dir=tmp_path / "events"), tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON
