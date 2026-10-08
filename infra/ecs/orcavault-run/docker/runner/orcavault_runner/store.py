"""Where a run keeps its results: S3 in AWS, or a directory when run locally.

Keys are relative to the store, and laid out as:

    <run ID>/summary.json
    <run ID>/event.json
    <run ID>/steps/<index>/run_results.json
"""

import json
import shutil
from pathlib import Path
from typing import Any, Protocol


class Store(Protocol):
    def get_json(self, key: str) -> Any:
        """Raises KeyError if there's nothing at key."""

    def put_json(self, key: str, value: Any) -> None: ...

    def get_file(self, key: str, path: Path) -> None:
        """Raises KeyError if there's nothing at key."""

    def put_file(self, key: str, path: Path) -> None: ...

    def location(self, key: str) -> str: ...


def summary_key(run_id: str) -> str:
    return f"{run_id}/summary.json"


def event_key(run_id: str) -> str:
    return f"{run_id}/event.json"


def results_key(run_id: str, step: int) -> str:
    return f"{run_id}/steps/{step}/run_results.json"


class S3Store:
    def __init__(self, bucket: str, prefix: str, client: Any = None) -> None:
        if client is None:
            import boto3

            client = boto3.client("s3")
        self.bucket = bucket
        self.prefix = prefix
        self.client = client

    def _key(self, key: str) -> str:
        return f"{self.prefix}{key}"

    def get_json(self, key: str) -> Any:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=self._key(key))
        except self.client.exceptions.NoSuchKey as e:
            raise KeyError(self.location(key)) from e
        return json.loads(response["Body"].read())

    def put_json(self, key: str, value: Any) -> None:
        self.client.put_object(
            Bucket=self.bucket,
            Key=self._key(key),
            Body=json.dumps(value, indent=2).encode(),
            ContentType="application/json",
        )

    def get_file(self, key: str, path: Path) -> None:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=self._key(key))
        except self.client.exceptions.NoSuchKey as e:
            raise KeyError(self.location(key)) from e
        path.write_bytes(response["Body"].read())

    def put_file(self, key: str, path: Path) -> None:
        # One PutObject, rather than upload_file, which splits large files into
        # a multipart upload that needs more permissions. The files are JSON of
        # a few MB at most.
        self.client.put_object(
            Bucket=self.bucket,
            Key=self._key(key),
            Body=path.read_bytes(),
            ContentType="application/json",
        )

    def location(self, key: str) -> str:
        return f"s3://{self.bucket}/{self._key(key)}"


class DirStore:
    def __init__(self, root: Path) -> None:
        self.root = root

    def _path(self, key: str) -> Path:
        return self.root / key

    def get_json(self, key: str) -> Any:
        try:
            return json.loads(self._path(key).read_text())
        except FileNotFoundError as e:
            raise KeyError(self.location(key)) from e

    def put_json(self, key: str, value: Any) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2))

    def get_file(self, key: str, path: Path) -> None:
        try:
            shutil.copyfile(self._path(key), path)
        except FileNotFoundError as e:
            raise KeyError(self.location(key)) from e

    def put_file(self, key: str, path: Path) -> None:
        target = self._path(key)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)

    def location(self, key: str) -> str:
        return str(self._path(key))
