"""Module related to running the dbt CLI."""

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
        """Stop the dbt process by sending a SIGINT.

        This will still write out the run_results.json.
        """
        self.stopping = True
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)

    def __call__(self, args: Sequence[str]) -> int:
        """Run the dbt command in the working directory and return the exit code."""
        log.info("Running: dbt %s", shlex.join(args))
        # This should run in its own session so that the SIGINT can be used later to
        # kill it if necessary.
        process = subprocess.Popen([*self.executable, *args], start_new_session=True)
        self.process = process
        if self.stopping:
            self.stop()

        code = process.wait()
        log.info("dbt exited with %d", code)
        return code
