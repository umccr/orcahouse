"""Running the dbt CLI.

dbt runs as a child process rather than through dbtRunner, so that the runner
can tell dbt to stop when ECS stops the task, and still record how it went.
"""

import logging
import shlex
import signal
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

log = logging.getLogger(__name__)

# Logged by the on-run-end hook in umccr/orcavault macros/ops/queries.sql, which
# only moves the CDC positions forward when every model succeeded.
POSITIONS_ADVANCED = "CDC positions updated to pending"
POSITIONS_HELD = "CDC positions not updated"


@dataclass(frozen=True)
class DbtExit:
    code: int
    # None when dbt didn't log either way, such as for a release without the
    # CDC watermark, or a command that doesn't run the hooks.
    positions_advanced: bool | None


class Dbt:
    def __init__(
        self,
        project_dir: Path,
        out: TextIO = sys.stdout,
        executable: Sequence[str] = ("dbt",),
    ) -> None:
        self.project_dir = project_dir
        self.out = out
        self.executable = list(executable)
        self.process: subprocess.Popen[str] | None = None
        self.stopping = False

    def stop(self, *_: object) -> None:
        """Signal handler for SIGTERM, which ECS sends when the task is stopped.

        dbt cancels its running queries on SIGINT, like Ctrl-C, and still writes
        run_results.json. If it hasn't exited by the container's stopTimeout,
        ECS kills it along with the runner, and the state machine sends the
        event instead.
        """
        self.stopping = True
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)

    def __call__(self, args: list[str]) -> DbtExit:
        log.info("Running: dbt %s", shlex.join(args))
        positions_advanced = None
        # In its own session, so that a Ctrl-C in a terminal reaches only the
        # runner, which passes it on, the same as SIGTERM.
        self.process = subprocess.Popen(
            [*self.executable, *args],
            cwd=self.project_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        # Stopped while dbt was starting.
        if self.stopping:
            self.stop()

        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.out.write(line)
            self.out.flush()
            if POSITIONS_ADVANCED in line:
                positions_advanced = True
            elif POSITIONS_HELD in line:
                positions_advanced = False

        code = self.process.wait()
        self.process = None
        log.info("dbt exited with %d", code)
        return DbtExit(code, positions_advanced)
