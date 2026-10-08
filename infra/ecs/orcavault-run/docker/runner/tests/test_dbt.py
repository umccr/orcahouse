import io
import signal
import sys
import textwrap
import time

import pytest

from orcavault_runner.dbt import Dbt

# Stands in for the dbt CLI: it logs its arguments and working directory, then
# acts on the first argument.
FAKE_DBT = textwrap.dedent(
    """
    import os, signal, sys, time

    print("args:", *sys.argv[1:], flush=True)
    print("cwd:", os.path.basename(os.getcwd()), flush=True)
    action = sys.argv[1]
    if action == "advance":
        print("03:12:00  CDC positions updated to pending", flush=True)
    elif action == "hold":
        print("03:12:00  CDC positions not updated: 2 models didn't succeed", flush=True)
    elif action == "wait":
        print("ready", flush=True)
        try:
            time.sleep(30)
        except KeyboardInterrupt:
            print("interrupted", flush=True)
            sys.exit(2)
    elif action == "hang":
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        print("ready", flush=True)
        time.sleep(30)
    sys.exit(int(sys.argv[2]))
    """
)


@pytest.fixture
def dbt(tmp_path, project_dir):
    script = tmp_path / "fake_dbt.py"
    script.write_text(FAKE_DBT)
    return Dbt(project_dir, out=io.StringIO(), executable=[sys.executable, script])


@pytest.mark.parametrize(
    "action, positions_advanced",
    [("advance", True), ("hold", False), ("other", None)],
)
def test_positions(dbt, action, positions_advanced):
    assert dbt([action, "0"]).positions_advanced is positions_advanced


def test_exit_code_and_output(dbt):
    dbt_exit = dbt(["other", "1", "--select", "+lims"])

    assert dbt_exit.code == 1
    assert dbt.out.getvalue() == "args: other 1 --select +lims\ncwd: orcavault\n"
    assert dbt.process is None


class StopWhenReady(io.StringIO):
    def __init__(self, dbt):
        super().__init__()
        self.dbt = dbt

    def write(self, s):
        if s == "ready\n":
            self.dbt.stop()
        return super().write(s)


@pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")
def test_stop(dbt):
    dbt.out = StopWhenReady(dbt)

    assert dbt(["wait", "0"]).code == 2
    assert dbt.out.getvalue().endswith("ready\ninterrupted\n")
    assert dbt.stopping


@pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")
def test_stopped_before_starting(dbt):
    dbt.stop()

    # Interrupted wherever it got to, rather than after sleeping.
    assert dbt(["wait", "0"]).code != 0


@pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")
def test_killed_when_it_doesnt_stop(dbt):
    dbt.kill_after_seconds = 0.5
    dbt.out = StopWhenReady(dbt)

    assert dbt(["hang", "0"]).code == -signal.SIGKILL
    assert dbt.killing


@pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")
def test_killed_before_starting(dbt):
    dbt.kill_after_seconds = 0
    dbt.stop()
    while not dbt.killing:
        time.sleep(0.01)

    assert dbt(["hang", "0"]).code == -signal.SIGKILL
