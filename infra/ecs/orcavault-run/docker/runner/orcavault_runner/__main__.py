"""This is the image entrypoint, which runs in the dbt project directory.

With no arguments it runs the request in ORCAVAULT_RUN_REQUEST, which is how
Step Functions starts it, see request.py. With arguments, such as debug, they go
to dbt as they are.

Environment:

    ORCAVAULT_RUN_REQUEST     The execution input. Empty is {}.
    ORCAVAULT_RUN_ID          The execution name. Defaults to manual-<time>.
    ORCAVAULT_RESULTS_BUCKET  Bucket for the run's event under runs/. Without
                              it, the event goes under runs/ in ORCAVAULT_RESULTS_DIR.

Variables specific to dbt are also read, such as DBT_TARGET.
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
    """The environment for the runner where each variable is ORCAVAULT_<field name>."""

    model_config = SettingsConfigDict(env_prefix="ORCAVAULT_", env_ignore_empty=True, frozen=True)

    run_request: str = "{}"
    run_id: str = Field(default_factory=lambda: datetime.now(UTC).strftime("manual-%Y%m%dT%H%M%SZ"))
    results_bucket: str | None = None
    results_dir: Path = Path("target")
    # This must be set in the Dockerfile to resolve to the ref in umccr/orcavault.
    ref: str | None = None


def write_event(event: Event, settings: Settings) -> str:
    """Write the event for the run and return the location.

    The location is `runs/<run_id>/event.json` in the results bucket, or otherwise the results directory.
    """
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
        format="%(asctime)s  [runner] %(levelname)s %(message)s",  # Similar to dbt style.
        datefmt="%H:%M:%S",
    )

    settings = Settings()
    # The image has the .git that was fetched for the ref, so it can be logged.
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
