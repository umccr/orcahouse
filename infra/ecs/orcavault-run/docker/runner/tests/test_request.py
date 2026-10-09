import json

import pytest

from orcavault_runner.request import Request, RequestError, parse_request


@pytest.mark.parametrize("raw", ["", "  ", "{}"])
def test_empty_request_builds_everything(raw):
    assert parse_request(raw) == Request(args=("build",))


def test_args_as_a_list():
    request = parse_request('{"args": ["build", "--select", "+lims", "fastq", "--full-refresh"]}')

    assert request.args == ("build", "--select", "+lims", "fastq", "--full-refresh")


def test_args_as_a_string_are_split_like_a_shell():
    request = parse_request(json.dumps({"args": """seed  --select mdm__workflow_run --vars '{"a": 1}'"""}))

    assert request.args == ("seed", "--select", "mdm__workflow_run", "--vars", '{"a": 1}')


@pytest.mark.parametrize("command", ["build", "run", "test", "seed", "snapshot"])
def test_commands(command):
    assert parse_request(json.dumps({"args": [command]})).args == (command,)


@pytest.mark.parametrize(
    "request_json, names",
    [
        ({"select": "lims"}, ["select"]),
        ({"args": ["build"], "retry": "run-1"}, ["retry"]),
        ({"select": "lims", "retry": "run-1"}, ["select", "retry"]),
        ({"args": ["run-operation", "drop_everything"]}, ["run-operation"]),
        ({"args": ["debug"]}, ["debug"]),
        ({"args": ["retry"]}, ["retry"]),
        ({"args": ["--select", "lims"]}, ["--select"]),
        ({"args": []}, ["args"]),
        ({"args": ""}, ["args"]),
        ({"args": "build --vars '{\"a\": 1}"}, ["args"]),
        ({"args": ["build", 1]}, ["args"]),
        ({"args": {"select": "lims"}}, ["args"]),
        ({"args": None}, ["args"]),
        ({"args": 1, "select": "lims"}, ["args", "select"]),
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
