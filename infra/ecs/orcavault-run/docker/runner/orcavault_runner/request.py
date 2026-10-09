"""What a run is asked to do.

A request is the Step Functions execution input, one of:

    {}                                          dbt build
    {"args": ["build", "--select", "+lims"]}    dbt with these arguments
    {"args": "build --select +lims"}            the same, split like a shell would

A run is one dbt command. To run several, start one execution after another.

The request is checked before dbt starts, so one that can't be right fails the
run straight away. dbt checks its own arguments.
"""

import json
import shlex

from pydantic import BaseModel, ConfigDict, ValidationError, field_validator
from pydantic_core import ErrorDetails, PydanticCustomError

# The dbt commands that build or test, which a run's outcome is made from.
# Others, such as debug or ls, go through the image's arguments, which records
# nothing, see __main__.py. run-operation is left out because it runs any macro
# with the task's grants.
COMMANDS = ("build", "run", "test", "seed", "snapshot")

# pydantic's errors, by type, in words for whoever started the run, since they
# end up in the run's event and Slack, where `...` is code. Others keep
# pydantic's message.
MESSAGES = {
    "json_invalid": "The request isn't valid JSON: {error}",
    "model_type": "The request must be a JSON object, not {input}",
    "tuple_type": "`args` must be a list of strings, or a string, not {input}",
    "string_type": "`args` item {item} must be a string, not {input}",
}


class RequestError(ValueError):
    """The request can't be right."""


class Request(BaseModel):
    """The dbt arguments to run."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    args: tuple[str, ...] = ("build",)

    @field_validator("args", mode="before")
    @classmethod
    def split(cls, value: object) -> object:
        # Quoted the way a shell would, so that --vars '{"a": 1}' is one argument.
        if not isinstance(value, str):
            return value
        try:
            return shlex.split(value)
        except ValueError as e:
            raise PydanticCustomError("split", "Can't split `args`: {error}", {"error": str(e)}) from e

    @field_validator("args")
    @classmethod
    def starts_with_a_command(cls, args: tuple[str, ...]) -> tuple[str, ...]:
        if not args or args[0] not in COMMANDS:
            commands = ", ".join(f"`{command}`" for command in COMMANDS)
            got = f"`{args[0]}`" if args else "nothing"
            raise PydanticCustomError(
                "command",
                "`args` must start with one of {commands}, not {got}",
                {"commands": commands, "got": got},
            )
        return args


def parse_request(raw: str) -> Request:
    """Parses the execution input, where an empty string is the same as {}."""
    try:
        return Request.model_validate_json(raw.strip() or "{}")
    except ValidationError as e:
        raise RequestError(describe(e.errors())) from e


def describe(errors: list[ErrorDetails]) -> str:
    # pydantic has an error for each unknown field, which are named together.
    unknown = sorted(f"`{error['loc'][0]}`" for error in errors if error["type"] == "extra_forbidden")
    messages = [message(error) for error in errors if error["type"] != "extra_forbidden"]
    if unknown:
        fields = "fields" if len(unknown) > 1 else "field"
        messages.insert(0, f"Unknown {fields} {', '.join(unknown)}. A request only has `args`")
    return ". ".join(messages)


def message(error: ErrorDetails) -> str:
    template = MESSAGES.get(error["type"])
    if template is None:
        return error["msg"]
    # Where in args, counting from one.
    item = error["loc"][-1] + 1 if error["loc"] and isinstance(error["loc"][-1], int) else ""
    got = f"`{json.dumps(error['input'], default=str)}`"
    return template.format(item=item, input=got, **error.get("ctx", {}))
