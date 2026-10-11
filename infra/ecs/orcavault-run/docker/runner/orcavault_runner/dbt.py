"""Running the dbt CLI.

dbt runs as a child process rather than through dbtRunner, so that the runner
can tell dbt to stop when ECS stops the task, and still record how it went.
"""

import logging
import shlex
import signal
import subprocess
from collections.abc import Sequence
from pathlib import Path

log = logging.getLogger(__name__)


class Dbt:
    def __init__(self, project_dir: Path, executable: Sequence[str] = ("dbt",)) -> None:
        self.project_dir = project_dir
        self.executable = list(executable)
        self.process: subprocess.Popen[bytes] | None = None
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

    def __call__(self, args: list[str]) -> int:
        """Runs dbt, which writes to the runner's stdout, and returns its exit
        code."""
        log.info("Running: dbt %s", shlex.join(args))
        # In its own session, so that a Ctrl-C in a terminal reaches only the
        # runner, which passes it on, the same as SIGTERM.
        self.process = subprocess.Popen([*self.executable, *args], cwd=self.project_dir, start_new_session=True)
        # Stopped while dbt was starting.
        if self.stopping:
            self.stop()

        code = self.process.wait()
        self.process = None
        log.info("dbt exited with %d", code)
        return code
