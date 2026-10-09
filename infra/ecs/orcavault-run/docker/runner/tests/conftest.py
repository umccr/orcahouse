from pathlib import Path

import pytest

from orcavault_runner.run import Config


@pytest.fixture
def project_dir(tmp_path: Path) -> Path:
    path = tmp_path / "orcavault"
    path.mkdir()
    return path


@pytest.fixture
def config(project_dir: Path) -> Config:
    return Config(
        run_id="run-1",
        environment="prod",
        project_dir=project_dir,
        orcavault_ref="v1.0.0",
        logs_url="https://logs",
    )
