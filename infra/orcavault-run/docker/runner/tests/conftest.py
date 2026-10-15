import pytest


@pytest.fixture(autouse=True)
def in_tmp_path(tmp_path, monkeypatch):
    """Each test should run in its own directory."""
    monkeypatch.chdir(tmp_path)
