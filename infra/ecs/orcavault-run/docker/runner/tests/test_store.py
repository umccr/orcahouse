import json

import boto3
from botocore.stub import Stubber

from orcavault_runner.store import DirStore, S3Store, event_key


def test_event_key():
    assert event_key("run-1") == "run-1/event.json"


def test_s3_store():
    client = boto3.client("s3", region_name="ap-southeast-2", aws_access_key_id="x", aws_secret_access_key="x")
    store = S3Store("bucket", "runs/", client)
    with Stubber(client) as stubber:
        stubber.add_response(
            "put_object",
            {},
            {
                "Bucket": "bucket",
                "Key": "runs/run-1/event.json",
                "Body": json.dumps({"outcome": "succeeded"}, indent=2).encode(),
                "ContentType": "application/json",
            },
        )

        store.put_json("run-1/event.json", {"outcome": "succeeded"})

        stubber.assert_no_pending_responses()
    assert store.location("run-1/event.json") == "s3://bucket/runs/run-1/event.json"


def test_dir_store(tmp_path):
    store = DirStore(tmp_path / "results")

    store.put_json("run-1/event.json", {"outcome": "succeeded"})

    assert json.loads((tmp_path / "results" / "run-1" / "event.json").read_text()) == {"outcome": "succeeded"}
    assert store.location("run-1/event.json") == str(tmp_path / "results" / "run-1" / "event.json")
