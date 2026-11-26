"""The unload step, which calls orcavault's UNLOAD procedure with the run_unload_schema operation.

See The unload in the README.

Environment:

    ORCAVAULT_UNLOAD_SCHEMA        The schema to unload, such as mart.
    ORCAVAULT_UNLOAD_S3_PATH       s3://<bucket>/<prefix>, without a trailing slash.
    ORCAVAULT_UNLOAD_IAM_ROLE_ARN  The role Redshift unloads with.
"""

import json
import re
from dataclasses import dataclass

from .results import Event, Outcome, UnloadOutcome
from .run import DbtCommand, clear_artifacts, finish, run_dbt

# run_unload_schema doesn't escape these, so none can have a quote.
IDENTIFIER = re.compile(r"[a-z_][a-z0-9_]{0,126}")
# No trailing slash, as the procedure adds one.
S3_PATH = re.compile(r"s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/[A-Za-z0-9_.=-]+)*")
IAM_ROLE_ARN = re.compile(r"arn:aws[a-z-]*:iam::\d{12}:role/[A-Za-z0-9+=,.@_/-]+")


class UnloadError(ValueError):
    """The unload isn't configured, or isn't configured correctly."""


@dataclass(frozen=True)
class Unload:
    """What to unload, where to, and with which role."""

    schema_name: str
    s3_path: str
    iam_role_arn: str

    @classmethod
    def from_environment(cls, schema: str | None, s3_path: str | None, iam_role_arn: str | None) -> "Unload":
        """Read the unload from the values of its ORCAVAULT_UNLOAD_ variables."""
        values = {
            "ORCAVAULT_UNLOAD_SCHEMA": (schema, IDENTIFIER),
            "ORCAVAULT_UNLOAD_S3_PATH": (s3_path, S3_PATH),
            "ORCAVAULT_UNLOAD_IAM_ROLE_ARN": (iam_role_arn, IAM_ROLE_ARN),
        }
        if missing := [name for name, (value, _) in values.items() if not value]:
            raise UnloadError(f"The unload isn't configured, set {', '.join(missing)}")

        for name, (value, pattern) in values.items():
            if not pattern.fullmatch(value or ""):
                raise UnloadError(f"{name} isn't valid: {value}")

        return cls(schema or "", s3_path or "", iam_role_arn or "")

    def operation(self) -> tuple[str, ...]:
        """The dbt operation that calls the procedure."""
        arguments = {"schema_name": self.schema_name, "s3_bucket_path": self.s3_path, "iam_role_arn": self.iam_role_arn}
        return "run-operation", "run_unload_schema", "--args", json.dumps(arguments)


def run_unload(dbt: DbtCommand, schema: str | None, s3_path: str | None, iam_role_arn: str | None) -> Event:
    """Run the unload and return the event.

    The working directory is expected to be the dbt project.
    """
    clear_artifacts()

    try:
        unload = Unload.from_environment(schema, s3_path, iam_role_arn)
    except UnloadError as e:
        event = Event(error=str(e))
    else:
        event = run_dbt(unload.operation(), dbt)

    event = finish(event, dbt)
    event.unload_outcome = UnloadOutcome.SUCCEEDED if event.outcome is Outcome.SUCCEEDED else UnloadOutcome.FAILED
    return event
