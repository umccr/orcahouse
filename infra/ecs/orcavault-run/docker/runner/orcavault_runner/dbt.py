"""Running the dbt CLI.

dbt runs as a child process rather than through dbtRunner, so that each step
starts clean, and the runner can tell dbt to stop when ECS stops the task.
"""

import logging
import shlex
import signal
import subprocess
import sys
import threading
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

log = logging.getLogger(__name__)

# Logged by the on-run-end hook in umccr/orcavault macros/ops/queries.sql, which
# only moves the CDC positions forward when every model succeeded.
POSITIONS_ADVANCED = "CDC positions updated to pending"
POSITIONS_HELD = "CDC positions not updated"

# ECS kills the task 120 seconds after stopping it, see stopTimeout in ecs.tf.
# dbt is killed before then if it hasn't exited, so that the runner can still
# write the results.
KILL_AFTER_SECONDS = 90


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
        kill_after_seconds: float = KILL_AFTER_SECONDS,
    ) -> None:
        self.project_dir = project_dir
        self.out = out
        self.executable = list(executable)
        self.kill_after_seconds = kill_after_seconds
        self.process: subprocess.Popen[str] | None = None
        self.stopping = False
        self.killing = False

    def stop(self, *_: object) -> None:
        """Signal handler for SIGTERM, which ECS sends when the task is stopped.

        dbt cancels its running queries on SIGINT, like Ctrl-C, and still writes
        run_results.json. It can take a while to, such as when it's waiting on a
        connection, so it's killed if it hasn't exited by kill_after_seconds.
        """
        if not self.stopping:
            self.stopping = True
            timer = threading.Timer(self.kill_after_seconds, self._kill)
            timer.daemon = True
            timer.start()
        self._interrupt()

    def _interrupt(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)

    def _kill(self) -> None:
        self.killing = True
        process = self.process
        if process is not None and process.poll() is None:
            log.warning("dbt didn't stop within %g seconds, killing it", self.kill_after_seconds)
            process.kill()

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
        if self.killing:
            self.process.kill()
        elif self.stopping:
            self._interrupt()

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
