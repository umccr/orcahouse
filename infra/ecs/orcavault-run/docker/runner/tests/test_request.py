import json

import pytest

from orcavault_runner.request import RequestError, parse_request


@pytest.mark.parametrize(
    "raw, args",
    [
        ("", ("build",)),
        ("{}", ("build",)),
        ('{"args": ["seed", "--select", "+lims", "--full-refresh"]}', ("seed", "--select", "+lims", "--full-refresh")),
        # Split like a shell.
        (json.dumps({"args": """snapshot  --vars '{"a": 1}'"""}), ("snapshot", "--vars", '{"a": 1}')),
    ],
)
def test_requests(raw, args):
    assert parse_request(raw).args == args


@pytest.mark.parametrize(
    "request_json, names",
    [
        ({"select": "lims", "retry": "run-1"}, ["select", "retry"]),
        ({"args": ["run-operation", "drop_everything"]}, ["run-operation"]),
        ({"args": ["--select", "lims"]}, ["--select"]),
        ({"args": []}, ["args"]),
        ({"args": "build --select 'lims"}, ["args"]),
        ({"args": ["build", 1]}, ["args"]),
        ({"args": None}, ["args"]),
        ([], []),
    ],
)
def test_invalid_requests(request_json, names):
    with pytest.raises(RequestError) as e:
        parse_request(json.dumps(request_json))

    # However it's worded, the message names what's wrong.
    for name in names:
        assert name in str(e.value)


def test_not_json():
    with pytest.raises(RequestError):
        parse_request("not json")
