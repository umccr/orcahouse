import pytest


@pytest.fixture(autouse=True)
def in_tmp_path(tmp_path, monkeypatch):
    """
    The runner works in the dbt project, which is the working directory, so
    each test works in an empty one of its own.
    """
    monkeypatch.chdir(tmp_path)
