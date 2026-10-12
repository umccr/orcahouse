import pytest


@pytest.fixture(autouse=True)
def in_tmp_path(tmp_path, monkeypatch):
    """Runs each test in an empty working directory of its own.

    The runner works in the dbt project, which is the working directory.
    """
    monkeypatch.chdir(tmp_path)
