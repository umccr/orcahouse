from pathlib import Path

import pytest


@pytest.fixture
def project_dir(tmp_path: Path) -> Path:
    path = tmp_path / "orcavault"
    path.mkdir()
    return path
