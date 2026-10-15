import os
import re
from pathlib import Path

import boto3
import pytest
from botocore.stub import Stubber

from orcavault_runner.__main__ import Settings, write_event
from orcavault_runner.results import Event


@pytest.fixture(autouse=True)
def unset_environment(monkeypatch):
    """Remove ORCAVAULT_ variables set in the shell running the tests, so the tests run in isolation."""
    for name in list(os.environ):
        if name.upper().startswith("ORCAVAULT_"):
            monkeypatch.delenv(name)


ENVIRONMENT = {
    "ORCAVAULT_RUN_REQUEST": '{"args": "build"}',
    "ORCAVAULT_RUN_ID": "scheduled-1970-01-01",
    "ORCAVAULT_RESULTS_BUCKET": "bucket",
    "ORCAVAULT_RESULTS_DIR": "events",
    "ORCAVAULT_REF": "v1.0.0",
}
EVENT = Event()
EVENT_JSON = EVENT.model_dump_json(indent=2)


def test_settings(monkeypatch):
    for name, value in ENVIRONMENT.items():
        monkeypatch.setenv(name, value)
    monkeypatch.setenv("ORCAVAULT_REDSHIFT_HOST", "localhost")

    fields = {name.removeprefix("ORCAVAULT_").lower(): value for name, value in ENVIRONMENT.items()}
    assert Settings().model_dump(mode="json") == fields


def test_empty_settings(monkeypatch):
    unset = Settings()
    for name in ENVIRONMENT:
        monkeypatch.setenv(name, "")

    empty = Settings()
    assert empty.model_dump(exclude={"run_id"}) == unset.model_dump(exclude={"run_id"})
    assert re.fullmatch(r"manual-\d{8}T\d{6}Z", empty.run_id)


def test_write_event_to_s3(monkeypatch):
    client = boto3.client("s3", region_name="ap-southeast-2")
    monkeypatch.setattr(boto3, "client", lambda service: client)

    with Stubber(client) as stubber:
        stubber.add_response(
            "put_object",
            {},
            {"Bucket": "bucket", "Key": "runs/run-1/event.json", "Body": EVENT_JSON, "ContentType": "application/json"},
        )

        location = write_event(EVENT, Settings(run_id="run-1", results_bucket="bucket"))
        stubber.assert_no_pending_responses()

    assert location == "s3://bucket/runs/run-1/event.json"


def test_write_event_to_directory():
    path = Path("target", "runs", "run-1", "event.json")
    assert write_event(EVENT, Settings(run_id="run-1")) == str(path)
    assert path.read_text() == EVENT_JSON
