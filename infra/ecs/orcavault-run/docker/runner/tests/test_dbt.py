import io
import sys
from pathlib import Path

import pytest

from orcavault_runner.dbt import Dbt, DbtExit

FAKE_DBT = Path(__file__).parent / "fake_dbt.py"

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")


@pytest.fixture
def dbt(project_dir):
    return Dbt(project_dir, out=io.StringIO(), executable=[sys.executable, FAKE_DBT], kill_after_seconds=0.5)


@pytest.mark.parametrize("action, positions_advanced", [("advance", True), ("hold", False), ("other", None)])
def test_dbt(dbt, action, positions_advanced):
    assert dbt([action, "1", "--select", "+lims"]) == DbtExit(1, positions_advanced)
    assert dbt.out.getvalue().startswith(f"args: {action} 1 --select +lims\ncwd: orcavault\n")


class StopWhenReady(io.StringIO):
    def __init__(self, dbt):
        super().__init__()
        self.dbt = dbt

    def write(self, s):
        if s == "ready\n":
            self.dbt.stop()
        return super().write(s)


# -9 is killed by SIGKILL, which Windows doesn't have.
@posix_only
@pytest.mark.parametrize("action, code", [("wait", 2), ("hang", -9)])
def test_stop(dbt, action, code):
    # Killed if it doesn't stop.
    dbt.out = StopWhenReady(dbt)

    assert dbt([action, "0"]).code == code


@posix_only
def test_stopped_before_starting(dbt):
    dbt.stop()

    # Interrupted wherever it got to, rather than after sleeping.
    assert dbt(["wait", "0"]).code != 0
