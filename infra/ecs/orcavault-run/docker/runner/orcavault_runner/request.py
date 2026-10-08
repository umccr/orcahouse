"""What a run is asked to do, and the dbt arguments for it.

A request is the Step Functions execution input. It is validated before dbt
starts, so a typo fails the run straight away rather than running something
other than what was asked for.
"""

import json
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, field_validator, model_validator

# Step Functions execution names are at most 80 characters of these. The run ID
# is part of the results' S3 keys, so nothing else is accepted.
RUN_ID_PATTERN = r"^[A-Za-z0-9_-]{1,80}$"

MAX_STEPS = 10


class Step(BaseModel):
    """One dbt invocation. The defaults build the whole project.

    build rather than run, so that tests run straight after the model they test,
    and a failing error-severity test skips the models downstream of it.

    fail_fast is off by default. A failed model only skips the models that
    depend on it, and everything else still loads. The CDC positions don't move
    unless every model succeeds, so the next run rereads the window that the
    failed models missed.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    command: Literal["build", "run", "test", "seed", "snapshot"] = "build"
    select: tuple[str, ...] = ()
    exclude: tuple[str, ...] = ()
    selector: str | None = None
    indirect_selection: Literal["eager", "buildable", "cautious", "empty"] | None = None
    fail_fast: bool = False
    full_refresh: bool = False
    vars: dict[str, Any] = Field(default_factory=dict)

    @field_validator("select", "exclude", mode="before")
    @classmethod
    def split_selectors(cls, value: Any) -> Any:
        # The dbt CLI separates selectors with spaces, so a string is read the
        # same way: "a b" is two selectors, and "a,b" is their intersection.
        return value.split() if isinstance(value, str) else value

    @model_validator(mode="after")
    def check_flags(self) -> "Step":
        if self.selector and (self.select or self.exclude):
            raise ValueError("selector can't be combined with select or exclude")
        if self.full_refresh and self.command not in ("build", "run", "seed"):
            raise ValueError(f"full_refresh doesn't apply to {self.command}")
        if self.indirect_selection and self.command not in ("build", "test"):
            raise ValueError(f"indirect_selection doesn't apply to {self.command}")
        return self

    def dbt_args(self, target: str) -> list[str]:
        args = [self.command, "--target", target]
        if self.command in ("build", "test"):
            # Unit tests check model logic against fixtures, which is CI's job.
            # In the warehouse they would only add queries.
            args += ["--exclude-resource-type", "unit_test"]
        if self.selector:
            args += ["--selector", self.selector]
        if self.select:
            args += ["--select", *self.select]
        if self.exclude:
            args += ["--exclude", *self.exclude]
        if self.indirect_selection:
            args += ["--indirect-selection", self.indirect_selection]
        if self.fail_fast:
            args.append("--fail-fast")
        if self.full_refresh:
            args.append("--full-refresh")
        if self.vars:
            args += ["--vars", json.dumps(self.vars)]
        return args


class RetryStep(BaseModel):
    """Reruns what didn't succeed in a step of an earlier run, with dbt retry.

    dbt retry reads the earlier step's run_results.json, which records its
    arguments, and runs only the nodes that failed or were skipped.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    command: Literal["retry"] = "retry"
    run: str = Field(pattern=RUN_ID_PATTERN)
    step: int = Field(ge=0)

    def dbt_args(self, target: str, state_dir: str) -> list[str]:
        return ["retry", "--target", target, "--state", state_dir]


PlannedStep = Step | RetryStep

planned_step = TypeAdapter(PlannedStep)


class Request(BaseModel):
    """The execution input.

    Either steps, run in order until one fails, or the ID of an earlier run to
    retry. A request without either is a single step, so the scheduled run's {}
    builds everything, and {"select": "+lims"} is shorthand for one step.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    steps: tuple[Step, ...] = Field(default=(), max_length=MAX_STEPS)
    retry: str | None = Field(default=None, pattern=RUN_ID_PATTERN)

    @model_validator(mode="before")
    @classmethod
    def single_step(cls, data: Any) -> Any:
        if isinstance(data, dict) and "steps" not in data and "retry" not in data:
            return {"steps": [data]}
        return data

    @model_validator(mode="after")
    def check_steps_or_retry(self) -> "Request":
        if bool(self.steps) == bool(self.retry):
            raise ValueError("a request has either steps or retry, and not both")
        return self


def parse_request(raw: str) -> Request:
    """Parses the execution input, where an empty string is the same as {}."""
    return Request.model_validate_json(raw.strip() or "{}")


def step_spec(step: PlannedStep) -> dict[str, Any]:
    """The step as JSON, which planned_step reads back. The command is always
    kept, because it tells a step from a retry."""
    return {"command": step.command, **step.model_dump(mode="json", exclude_defaults=True)}
