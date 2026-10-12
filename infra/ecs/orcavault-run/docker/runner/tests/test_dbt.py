import sys
import threading
from pathlib import Path

import pytest

from orcavault_runner.dbt import Dbt

FAKE_DBT = Path(__file__).parent / "fake_dbt.py"

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="SIGINT can't be sent to a process on Windows")


@pytest.fixture
def dbt():
    return Dbt(executable=[sys.executable, FAKE_DBT])


def test_dbt(dbt, capfd):
    assert dbt(["exit", "1", "--select", "+lims"]) == 1
    # Straight to the runner's stdout.
    assert capfd.readouterr().out.splitlines() == ["args: exit 1 --select +lims"]


@posix_only
def test_stop(dbt):
    threading.Timer(0.5, dbt.stop).start()

    # Interrupted, rather than after sleeping.
    assert dbt(["wait", "0"]) != 0


@posix_only
def test_stopped_before_starting(dbt):
    dbt.stop()

    # Interrupted wherever it got to, rather than after sleeping.
    assert dbt(["wait", "0"]) != 0
