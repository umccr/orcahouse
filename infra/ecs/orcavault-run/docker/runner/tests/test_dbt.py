import sys
import threading
from pathlib import Path

import pytest

from orcavault_runner.dbt import Dbt

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="SIGINT tests can't run on Windows")


@pytest.fixture
def dbt():
    return Dbt(executable=[sys.executable, str(Path(__file__).parent / "mock_dbt.py")])


def test_dbt(dbt, capfd):
    assert dbt(["exit", "1", "--select", "+lims"]) == 1
    assert capfd.readouterr().out.splitlines() == ["args: exit 1 --select +lims"]


@posix_only
def test_stop(dbt):
    threading.Timer(0.5, dbt.stop).start()
    assert dbt(["wait", "0"]) != 0


@posix_only
def test_stop_no_start(dbt):
    dbt.stop()
    assert dbt(["wait", "0"]) != 0
