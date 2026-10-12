"""Running the dbt CLI.

dbt runs as a child process rather than through dbtRunner, so that the runner
can tell dbt to stop when ECS stops the task, and still record how it went.
"""

import logging
import shlex
import signal
import subprocess
from collections.abc import Sequence

log = logging.getLogger(__name__)


class Dbt:
    def __init__(self, executable: Sequence[str] = ("dbt",)) -> None:
        self.executable = executable
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

    def __call__(self, args: Sequence[str]) -> int:
        """Runs dbt in the working directory, and returns its exit code.

        dbt writes to the runner's stdout.
        """
        log.info("Running: dbt %s", shlex.join(args))
        # In its own session, so that a Ctrl-C in a terminal reaches only the
        # runner, which passes it on, the same as SIGTERM.
        self.process = subprocess.Popen([*self.executable, *args], start_new_session=True)
        # Stopped before dbt started, or while it was starting.
        if self.stopping:
            self.stop()

        code = self.process.wait()
        log.info("dbt exited with %d", code)
        return code
