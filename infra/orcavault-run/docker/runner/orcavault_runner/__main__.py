"""This is the image entrypoint, which runs in the dbt project directory.

With no arguments it runs the request in ORCAVAULT_RUN_REQUEST, which is how
Step Functions starts it, see request.py. With arguments, such as debug, they go
to dbt as they are.

Environment:

    ORCAVAULT_RUN_REQUEST     The execution input. Empty is {}.
    ORCAVAULT_RUN_ID          The execution name. Defaults to manual-<time>.
    ORCAVAULT_RESULTS_BUCKET  Bucket for the run's event under runs/, its dbt
                              run_results.json and manifest.json under v1/, and
                              its manifest at state/manifest.json. Without it,
                              the event goes under runs/ in ORCAVAULT_RESULTS_DIR.

Variables specific to dbt are also read, such as DBT_TARGET.
"""

import logging
import os
import signal
import sys
from datetime import UTC, datetime
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from .dbt import Dbt
from .results import Event
from .run import run

log = logging.getLogger(__name__)

# The dbt artifacts of each run that are kept under v1/<name>/.
ARTIFACTS = ("run_results", "manifest")


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


def write_manifest(settings: Settings) -> str | None:
    """Write the dbt manifest of the run and return the location."""
    path = Path("target", "manifest.json")
    bucket = settings.results_bucket
    if not bucket or not path.exists():
        return None

    key = "state/manifest.json"
    boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=path.read_bytes(), ContentType="application/json")
    return f"s3://{bucket}/{key}"


def write_artifact(name: str, settings: Settings, started_at: datetime) -> str | None:
    """Write dbt's <name>.json and return the location.

    The location is `v1/<name>/year=<YYYY>/month=<MM>/day=<DD>/<run_id>/<name>.json`, a Hive style
    partition by the UTC date the run started. The run_results Athena table reads `v1/run_results/`.
    """
    path = Path("target", f"{name}.json")
    bucket = settings.results_bucket
    if not bucket or not path.exists():
        return None

    partition = started_at.astimezone(UTC).strftime("year=%Y/month=%m/day=%d")
    key = f"v1/{name}/{partition}/{settings.run_id}/{name}.json"
    boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=path.read_bytes(), ContentType="application/json")
    return f"s3://{bucket}/{key}"


def main() -> int:
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="%(asctime)s  [runner] %(levelname)s %(message)s",  # Similar to dbt style.
        datefmt="%H:%M:%S",
    )

    settings = Settings()
    # dbt adds this to the metadata.env of its artifacts, such as run_results.json.
    os.environ["DBT_ENV_CUSTOM_ENV_RUN_ID"] = settings.run_id

    # The image has the .git that was fetched for the ref, so it can be logged.
    commit_file = Path(".git/HEAD")
    commit = commit_file.read_text().strip() if commit_file.exists() else "unknown"
    log.info("umccr/orcavault %s at %s", settings.ref, commit)

    if len(sys.argv) > 1:
        os.execvp("dbt", ["dbt", *sys.argv[1:]])

    dbt = Dbt()
    signal.signal(signal.SIGTERM, dbt.stop)
    signal.signal(signal.SIGINT, dbt.stop)

    started_at = datetime.now(UTC)
    event = run(settings.run_request, dbt)
    location = write_event(event, settings)
    log.info("Run %s: %s, event at %s", settings.run_id, event.outcome, location)

    # The run has finished, so failing to write these shouldn't change the outcome.
    try:
        if manifest := write_manifest(settings):
            log.info("Manifest at %s", manifest)
    except (BotoCoreError, ClientError):
        log.exception("Failed to write the manifest")

    for name in ARTIFACTS:
        try:
            if location := write_artifact(name, settings, started_at):
                log.info("%s at %s", name, location)
        except (BotoCoreError, ClientError):
            log.exception("Failed to write %s", name)

    return event.outcome.exit_code


if __name__ == "__main__":
    sys.exit(main())
