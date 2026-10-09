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

dbt reads its own variables as well, such as DBT_TARGET. The image sets a few,
see the Dockerfile.
"""

import json
import logging
import os
import signal
import sys
import urllib.request
from collections.abc import Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

import boto3

from .dbt import Dbt
from .run import Config, run

log = logging.getLogger("orcavault_runner")

RESULTS_PREFIX = "runs/"


def console_logs_url(region: str, group: str, stream: str) -> str:
    # The console escapes names twice, with $ in place of %.
    def escape(name: str) -> str:
        return quote(quote(name, safe=""), safe="").replace("%", "$")

    return (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}"
        f"#logsV2:log-groups/log-group/{escape(group)}/log-events/{escape(stream)}"
    )


def ecs_logs_url(environ: Mapping[str, str]) -> str | None:
    """This container's CloudWatch log stream, from the ECS task metadata.

    https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-metadata-endpoint-v4-fargate.html
    """
    uri = environ.get("ECS_CONTAINER_METADATA_URI_V4")
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


def write_event(event: dict[str, Any], environ: Mapping[str, str], project_dir: Path) -> str:
    """Writes the run's event to <run ID>/event.json, under runs/ in the results
    bucket, or else in a directory, and returns where it went."""
    key = f"{event['runId']}/event.json"
    body = json.dumps(event, indent=2)
    bucket = environ.get("ORCAVAULT_RESULTS_BUCKET")
    if bucket:
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=RESULTS_PREFIX + key,
            Body=body.encode(),
            ContentType="application/json",
        )
        return f"s3://{bucket}/{RESULTS_PREFIX}{key}"

    path = Path(environ.get("ORCAVAULT_RESULTS_DIR", project_dir / "target" / "runs")) / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    return str(path)


def run_id(environ: Mapping[str, str]) -> str:
    return environ.get("ORCAVAULT_RUN_ID") or datetime.now(timezone.utc).strftime("manual-%Y%m%dT%H%M%SZ")


def main(argv: list[str], environ: Mapping[str, str]) -> int:
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="%(asctime)s  [runner] %(message)s",
        datefmt="%H:%M:%S",
    )

    project_dir = Path.cwd()
    commit_file = project_dir / "ORCAVAULT_COMMIT"
    commit = commit_file.read_text().strip() if commit_file.exists() else "unknown"
    ref = environ.get("ORCAVAULT_REF", "unknown")
    log.info("umccr/orcavault %s at %s", ref, commit)

    if argv:
        sys.stdout.flush()
        os.execvp("dbt", ["dbt", *argv])

    config = Config(
        run_id=run_id(environ),
        environment=environ.get("ORCAVAULT_ENVIRONMENT", "local"),
        project_dir=project_dir,
        orcavault_ref=ref,
        logs_url=ecs_logs_url(environ),
    )
    dbt = Dbt(project_dir)
    signal.signal(signal.SIGTERM, dbt.stop)
    signal.signal(signal.SIGINT, dbt.stop)

    outcome, event = run(environ.get("ORCAVAULT_RUN_REQUEST", ""), config, dbt)
    location = write_event(event, environ, project_dir)
    log.info("Run %s: %s, event at %s", config.run_id, outcome, location)
    return outcome.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))
