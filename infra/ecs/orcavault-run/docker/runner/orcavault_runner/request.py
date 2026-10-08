"""What a run is asked to do.

A request is the Step Functions execution input, one of:

    {}                                          dbt build
    {"args": ["build", "--select", "+lims"]}    dbt with these arguments
    {"args": "build --select +lims"}            the same, split like a shell would
    {"retry": "<run ID>"}                       what didn't succeed in that run

A run is one dbt command. To run several, start one execution after another.

The request is checked before dbt starts, so one that can't be right fails the
run straight away. dbt checks its own arguments.
"""

import json
import re
import shlex
from dataclasses import dataclass
from typing import Any

# Step Functions execution names are at most 80 characters of these. The run ID
# is part of the results' S3 keys, so nothing else is accepted.
RUN_ID_PATTERN = r"^[A-Za-z0-9_-]{1,80}$"

# The dbt commands that build or test, which a run's outcome is made from.
# Others, such as debug or ls, go through the image's arguments, which records
# nothing, see __main__.py. run-operation is left out because it runs any macro
# with the task's grants.
COMMANDS = ("build", "run", "test", "seed", "snapshot")


class RequestError(ValueError):
    """The request can't be right."""


@dataclass(frozen=True)
class Request:
    """dbt arguments, or the ID of an earlier run to retry."""

    args: tuple[str, ...] = ("build",)
    retry: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {"retry": self.retry} if self.retry else {"args": list(self.args)}


def parse_request(raw: str) -> Request:
    """Parses the execution input, where an empty string is the same as {}."""
    try:
        value = json.loads(raw.strip() or "{}")
    except json.JSONDecodeError as e:
        raise RequestError(f"The request isn't valid JSON: {e}") from e
    if not isinstance(value, dict):
        raise RequestError("The request must be a JSON object")

    unknown = sorted(set(value) - {"args", "retry"})
    if unknown:
        raise RequestError(f"Unknown field {', '.join(unknown)}. A request has args or retry")
    if "args" in value and "retry" in value:
        raise RequestError("A request has args or retry, not both")

    if "retry" in value:
        retry = value["retry"]
        if not isinstance(retry, str) or not re.match(RUN_ID_PATTERN, retry):
            raise RequestError(f"retry must be a run ID matching {RUN_ID_PATTERN}: {retry!r}")
        return Request(args=(), retry=retry)

    return Request(args=dbt_args(value.get("args", ["build"])))


def dbt_args(value: Any) -> tuple[str, ...]:
    if isinstance(value, str):
        # Quoted the way a shell would, so that --vars '{"a": 1}' is one argument.
        try:
            args = shlex.split(value)
        except ValueError as e:
            raise RequestError(f"Can't split args: {e}") from e
    elif isinstance(value, list) and all(isinstance(arg, str) for arg in value):
        args = value
    else:
        raise RequestError("args must be a list of strings, or a string")

    if args[:1] == ["retry"]:
        raise RequestError('To retry a run, request {"retry": "<run ID>"}')
    if not args or args[0] not in COMMANDS:
        got = repr(args[0]) if args else "nothing"
        raise RequestError(f"args must start with one of {', '.join(COMMANDS)}, not {got}")
    return tuple(args)
