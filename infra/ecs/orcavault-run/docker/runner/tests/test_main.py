import json
import re

import boto3
import pytest
from botocore.stub import Stubber

from orcavault_runner.__main__ import console_logs_url, ecs_logs_url, run_id, write_event
from orcavault_runner.run import Event

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

    assert ecs_logs_url({"ECS_CONTAINER_METADATA_URI_V4": metadata.as_uri()}) == LOGS_URL


@pytest.mark.parametrize("content", [None, "{}", "not json"])
def test_no_ecs_logs_url(tmp_path, content):
    metadata = tmp_path / "metadata.json"
    if content is not None:
        metadata.write_text(content)

    assert ecs_logs_url({"ECS_CONTAINER_METADATA_URI_V4": metadata.as_uri()}) is None
    assert ecs_logs_url({}) is None


def test_run_id():
    assert run_id({"ORCAVAULT_RUN_ID": "scheduled-2026-10-08"}) == "scheduled-2026-10-08"
    assert re.fullmatch(r"manual-\d{8}T\d{6}Z", run_id({}))


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

        location = write_event(EVENT, {"ORCAVAULT_RESULTS_BUCKET": "bucket"}, tmp_path)

        stubber.assert_no_pending_responses()
    assert location == "s3://bucket/runs/run-1/event.json"


def test_write_event_to_a_directory(tmp_path):
    path = tmp_path / "target" / "runs" / "run-1" / "event.json"
    assert write_event(EVENT, {}, tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON

    path = tmp_path / "events" / "run-1" / "event.json"
    assert write_event(EVENT, {"ORCAVAULT_RESULTS_DIR": str(tmp_path / "events")}, tmp_path) == str(path)
    assert path.read_text() == EVENT_JSON
