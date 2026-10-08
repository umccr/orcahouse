import json
import re

import pytest

from orcavault_runner.__main__ import console_logs_url, ecs_logs_url, make_store, run_id
from orcavault_runner.store import DirStore, S3Store

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
    with pytest.raises(SystemExit, match="must match"):
        run_id({"ORCAVAULT_RUN_ID": "a/b"})


def test_make_store(tmp_path, monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "ap-southeast-2")
    s3 = make_store({"ORCAVAULT_RESULTS_BUCKET": "bucket"}, tmp_path)
    assert isinstance(s3, S3Store)
    assert s3.location("run-1/summary.json") == "s3://bucket/runs/run-1/summary.json"

    assert make_store({}, tmp_path).root == tmp_path / "target" / "runs"
    assert make_store({"ORCAVAULT_RESULTS_DIR": str(tmp_path / "x")}, tmp_path).root == tmp_path / "x"
    assert isinstance(make_store({}, tmp_path), DirStore)
