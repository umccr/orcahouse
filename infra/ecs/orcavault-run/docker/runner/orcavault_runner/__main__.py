"""The image's entrypoint.

With no arguments it runs the request in ORCAVAULT_RUN_REQUEST, which is how
Step Functions starts it, see request.py. With arguments, such as debug, they go
to dbt as they are, and nothing is recorded.

Environment:

    ORCAVAULT_RUN_REQUEST     The execution input. Empty is the same as {}.
    ORCAVAULT_RUN_ID          The execution name. Defaults to manual-<time>.
    ORCAVAULT_RESULTS_BUCKET  Bucket for the run's event, under runs/. Without
                              it, the event goes to ORCAVAULT_RESULTS_DIR, or
                              target/runs.
    ORCAVAULT_ENVIRONMENT     Named in the run's event, such as prod.

They're read into Settings, where one that's empty is the same as unset.

dbt reads its own variables as well, such as DBT_TARGET. The image sets a few,
see the Dockerfile.
"""

import json
import logging
import os
import signal
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

import boto3
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from .dbt import Dbt
from .run import Config, Event, run

log = logging.getLogger("orcavault_runner")

RESULTS_PREFIX = "runs/"


def manual_run_id() -> str:
    return datetime.now(timezone.utc).strftime("manual-%Y%m%dT%H%M%SZ")


class Settings(BaseSettings):
    """The environment above, where each variable is ORCAVAULT_ and its field's
    name. Other ORCAVAULT_ variables, such as dbt's ORCAVAULT_REDSHIFT_HOST, are
    ignored."""

    model_config = SettingsConfigDict(env_prefix="ORCAVAULT_", env_ignore_empty=True, frozen=True)

    run_request: str = ""
    run_id: str = Field(default_factory=manual_run_id)
    results_bucket: str | None = None
    results_dir: Path | None = None
    environment: str = "local"
    # The umccr/orcavault ref in the image, which the Dockerfile sets.
    ref: str = "unknown"
    # Set by ECS, for the run's logs URL.
    ecs_metadata_uri: str | None = Field(None, validation_alias="ECS_CONTAINER_METADATA_URI_V4")


def console_logs_url(region: str, group: str, stream: str) -> str:
    # The console escapes names twice, with $ in place of %.
    def escape(name: str) -> str:
        return quote(quote(name, safe=""), safe="").replace("%", "$")

    return (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}"
        f"#logsV2:log-groups/log-group/{escape(group)}/log-events/{escape(stream)}"
    )


def ecs_logs_url(uri: str | None) -> str | None:
    """This container's CloudWatch log stream, from the ECS task metadata.

    https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint-v4-fargate.html
    """
    if not uri:
        return None
    try:
        with urllib.request.urlopen(uri, timeout=5) as response:
            options = json.load(response).get("LogOptions", {})
    except (OSError, ValueError) as e:
        log.warning("Couldn't read the task metadata: %s", e)
        return None

    region, group, stream = (options.get(k) for k in ("awslogs-region", "awslogs-group", "awslogs-stream"))
    if not (region and group and stream):
        return None
    return console_logs_url(region, group, stream)


def write_event(event: Event, settings: Settings, project_dir: Path) -> str:
    """Writes the run's event to <run ID>/event.json, under runs/ in the results
    bucket, or else in a directory, and returns where it went."""
    key = f"{event.run_id}/event.json"
    body = event.model_dump_json(indent=2)
    bucket = settings.results_bucket
    if bucket:
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=RESULTS_PREFIX + key,
            Body=body.encode(),
            ContentType="application/json",
        )
        return f"s3://{bucket}/{RESULTS_PREFIX}{key}"

    path = (settings.results_dir or project_dir / "target" / "runs") / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    return str(path)


def main(argv: list[str], settings: Settings) -> int:
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="%(asctime)s  [runner] %(message)s",
        datefmt="%H:%M:%S",
    )

    project_dir = Path.cwd()
    commit_file = project_dir / "ORCAVAULT_COMMIT"
    commit = commit_file.read_text().strip() if commit_file.exists() else "unknown"
    log.info("umccr/orcavault %s at %s", settings.ref, commit)

    if argv:
        sys.stdout.flush()
        os.execvp("dbt", ["dbt", *argv])

    config = Config(
        run_id=settings.run_id,
        environment=settings.environment,
        project_dir=project_dir,
        orcavault_ref=settings.ref,
        logs_url=ecs_logs_url(settings.ecs_metadata_uri),
    )
    dbt = Dbt(project_dir)
    signal.signal(signal.SIGTERM, dbt.stop)
    signal.signal(signal.SIGINT, dbt.stop)

    outcome, event = run(settings.run_request, config, dbt)
    location = write_event(event, settings, project_dir)
    log.info("Run %s: %s, event at %s", config.run_id, outcome, location)
    return outcome.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], Settings()))
