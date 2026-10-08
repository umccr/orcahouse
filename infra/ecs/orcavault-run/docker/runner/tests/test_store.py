import io
import json

import boto3
import pytest
from botocore.response import StreamingBody
from botocore.stub import ANY, Stubber

from orcavault_runner.store import DirStore, S3Store, event_key, results_key, summary_key


def body(data: bytes) -> StreamingBody:
    return StreamingBody(io.BytesIO(data), len(data))


@pytest.fixture
def s3():
    client = boto3.client("s3", region_name="ap-southeast-2", aws_access_key_id="x", aws_secret_access_key="x")
    with Stubber(client) as stubber:
        yield S3Store("bucket", "runs/", client), stubber
        stubber.assert_no_pending_responses()


def test_keys():
    assert summary_key("run-1") == "run-1/summary.json"
    assert event_key("run-1") == "run-1/event.json"
    assert results_key("run-1", 2) == "run-1/steps/2/run_results.json"


def test_s3_json(s3):
    store, stubber = s3
    stubber.add_response(
        "put_object",
        {},
        {"Bucket": "bucket", "Key": "runs/run-1/summary.json", "Body": ANY, "ContentType": "application/json"},
    )
    stubber.add_response(
        "get_object",
        {"Body": body(b'{"outcome": "succeeded"}')},
        {"Bucket": "bucket", "Key": "runs/run-1/summary.json"},
    )

    store.put_json("run-1/summary.json", {"outcome": "succeeded"})

    assert store.get_json("run-1/summary.json") == {"outcome": "succeeded"}
    assert store.location("run-1/summary.json") == "s3://bucket/runs/run-1/summary.json"


def test_s3_files(s3, tmp_path):
    store, stubber = s3
    source = tmp_path / "source.json"
    source.write_text('{"results": []}')
    stubber.add_response(
        "put_object",
        {},
        {"Bucket": "bucket", "Key": "runs/k", "Body": b'{"results": []}', "ContentType": "application/json"},
    )
    stubber.add_response("get_object", {"Body": body(b'{"results": []}')}, {"Bucket": "bucket", "Key": "runs/k"})

    store.put_file("k", source)
    store.get_file("k", tmp_path / "copy.json")

    assert json.loads((tmp_path / "copy.json").read_text()) == {"results": []}


@pytest.mark.parametrize("method", ["get_json", "get_file"])
def test_s3_missing(s3, tmp_path, method):
    store, stubber = s3
    stubber.add_client_error("get_object", service_error_code="NoSuchKey", http_status_code=404)

    with pytest.raises(KeyError, match="s3://bucket/runs/missing"):
        if method == "get_json":
            store.get_json("missing")
        else:
            store.get_file("missing", tmp_path / "copy.json")


def test_dir_store(tmp_path):
    store = DirStore(tmp_path / "results")
    source = tmp_path / "source.json"
    source.write_text('{"results": []}')

    store.put_json("run-1/summary.json", {"outcome": "succeeded"})
    store.put_file("run-1/steps/0/run_results.json", source)
    store.get_file("run-1/steps/0/run_results.json", tmp_path / "copy.json")

    assert store.get_json("run-1/summary.json") == {"outcome": "succeeded"}
    assert (tmp_path / "copy.json").read_text() == '{"results": []}'
    with pytest.raises(KeyError):
        store.get_json("missing")
    with pytest.raises(KeyError):
        store.get_file("missing", tmp_path / "x")
