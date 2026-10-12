"""The image's entrypoint, which runs in the dbt project's directory.

With no arguments it runs the request in ORCAVAULT_RUN_REQUEST, which is how
Step Functions starts it, see request.py. With arguments, such as debug, they go
to dbt as they are, and nothing is recorded.

Environment:

    ORCAVAULT_RUN_REQUEST     The execution input. Empty is the same as {}.
    ORCAVAULT_RUN_ID          The execution name. Defaults to manual-<time>.
    ORCAVAULT_RESULTS_BUCKET  Bucket for the run's event, under runs/. Without
                              it, the event goes under runs/ in
                              ORCAVAULT_RESULTS_DIR, or target.

They're read into Settings, where one that's empty is the same as unset.

dbt reads its own variables as well, such as DBT_TARGET. The image sets a few,
see the Dockerfile.
"""

import logging
import os
import signal
import sys
from datetime import UTC, datetime
from pathlib import Path

import boto3
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from .dbt import Dbt
from .results import Event
from .run import run

log = logging.getLogger(__name__)


class Settings(BaseSettings):
    """The environment above, where each variable is ORCAVAULT_ and its field's
    name. Other ORCAVAULT_ variables, such as dbt's ORCAVAULT_REDSHIFT_HOST, are
    ignored."""

    model_config = SettingsConfigDict(env_prefix="ORCAVAULT_", env_ignore_empty=True, frozen=True)

    run_request: str = "{}"
    run_id: str = Field(default_factory=lambda: datetime.now(UTC).strftime("manual-%Y%m%dT%H%M%SZ"))
    results_bucket: str | None = None
    results_dir: Path = Path("target")
    # The umccr/orcavault ref in the image, which the Dockerfile sets.
    ref: str = "unknown"


def write_event(event: Event, settings: Settings) -> str:
    """Writes the run's event to runs/<run ID>/event.json, in the results bucket
    or else the results directory, and returns where it went."""
    key = f"runs/{settings.run_id}/event.json"
    body = event.model_dump_json(indent=2)
    if bucket := settings.results_bucket:
        boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
        return f"s3://{bucket}/{key}"

    path = settings.results_dir / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    return str(path)


def main() -> int:
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="%(asctime)s  [runner] %(message)s",
        datefmt="%H:%M:%S",
    )

    settings = Settings()
    # The image keeps the .git that fetched the ref, at the commit it resolved to.
    commit_file = Path(".git/HEAD")
    commit = commit_file.read_text().strip() if commit_file.exists() else "unknown"
    log.info("umccr/orcavault %s at %s", settings.ref, commit)

    if len(sys.argv) > 1:
        os.execvp("dbt", ["dbt", *sys.argv[1:]])

    dbt = Dbt()
    signal.signal(signal.SIGTERM, dbt.stop)
    signal.signal(signal.SIGINT, dbt.stop)

    event = run(settings.run_request, dbt)
    location = write_event(event, settings)
    log.info("Run %s: %s, event at %s", settings.run_id, event.outcome, location)
    return event.outcome.exit_code


if __name__ == "__main__":
    sys.exit(main())
