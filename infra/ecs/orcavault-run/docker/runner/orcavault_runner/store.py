"""Where a run writes its event: S3 in AWS, or a directory when run locally.

Keys are relative to the store, and laid out as:

    <run ID>/event.json
"""

import json
from pathlib import Path
from typing import Any, Protocol


class Store(Protocol):
    def put_json(self, key: str, value: Any) -> None: ...

    def location(self, key: str) -> str: ...


def event_key(run_id: str) -> str:
    return f"{run_id}/event.json"


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

    def put_json(self, key: str, value: Any) -> None:
        self.client.put_object(
            Bucket=self.bucket,
            Key=self._key(key),
            Body=json.dumps(value, indent=2).encode(),
            ContentType="application/json",
        )

    def location(self, key: str) -> str:
        return f"s3://{self.bucket}/{self._key(key)}"


class DirStore:
    def __init__(self, root: Path) -> None:
        self.root = root

    def _path(self, key: str) -> Path:
        return self.root / key

    def put_json(self, key: str, value: Any) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2))

    def location(self, key: str) -> str:
        return str(self._path(key))
