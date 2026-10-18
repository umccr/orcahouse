import json

import pytest

from orcavault_runner.request import RequestError, parse_request


@pytest.mark.parametrize(
    "raw, args",
    [
        ("{}", ("build",)),
        ('{"args": ["seed", "--select", "+lims", "--full-refresh"]}', ("seed", "--select", "+lims", "--full-refresh")),
        (json.dumps({"args": """snapshot  --vars '{"a": 1}'"""}), ("snapshot", "--vars", '{"a": 1}')),
    ],
)
def test_requests(raw, args):
    assert parse_request(raw) == args


@pytest.mark.parametrize(
    "raw, names",
    [
        ('{"select": "lims", "retry": "run-1"}', ["select", "retry"]),
        ('{"args": ["run-operation", "drop_everything"]}', ["run-operation"]),
        ('{"args": ["--select", "lims"]}', ["--select"]),
        ('{"args": []}', ["args"]),
        (json.dumps({"args": "build --select 'lims"}), ["args"]),
        ('{"args": ["build", 1]}', ["args"]),
        ('{"args": "build --target-path elsewhere"}', ["--target-path"]),
        ('{"args": ["run", "--no-write-json"]}', ["--no-write-json"]),
        ('{"args": null}', ["args"]),
        ("[]", []),
        ("not json", []),
    ],
)
def test_invalid_requests(raw, names):
    with pytest.raises(RequestError) as e:
        parse_request(raw)

    for name in names:
        assert name in str(e.value)
