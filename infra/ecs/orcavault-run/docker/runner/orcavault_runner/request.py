"""The specific run request.

A request is the Step Functions execution input, e.g.:

    {}                                          dbt build
    {"args": ["build", "--select", "+lims"]}    dbt with these arguments

A run is one dbt command. To run several, start one execution after another.
"""

import json
import shlex

# The dbt commands that are supported by a request.
COMMANDS = ("build", "run", "test", "seed", "snapshot")


class RequestError(ValueError):
    """A request error."""


def parse_request(raw: str) -> tuple[str, ...]:
    """Parse the execution request into dbt args."""
    try:
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RequestError(f"The request isn't valid JSON: {e}") from e

    if not isinstance(request, dict):
        raise RequestError(f"The request must be a JSON object, not `{raw}`")

    unknown = sorted(request.keys() - {"args"})
    if unknown:
        names = ", ".join(f"`{name}`" for name in unknown)
        raise RequestError(f"The request only has `args`, not {names}")

    args: object = request.get("args", ["build"])
    if isinstance(args, str):
        try:
            args = shlex.split(args)
        except ValueError as e:
            raise RequestError(f"Can't split `args`: {e}") from e

    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise RequestError(f"`args` must be a list of strings, or a string, not `{json.dumps(args)}`")

    if not args or args[0] not in COMMANDS:
        commands = ", ".join(f"`{command}`" for command in COMMANDS)
        received = f"`{args[0]}`" if args else "nothing"
        raise RequestError(f"`args` must start with one of {commands}, not {received}")

    return tuple(args)
