import json
import re

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
    "request_json, message",
    [
        ({"select": "lims"}, "Unknown field select. A request only has args"),
        ({"args": ["build"], "retry": "run-1"}, "Unknown field retry"),
        ({"args": ["run-operation", "drop_everything"]}, "args must start with one of build, run, test, seed, snapshot, not 'run-operation'"),
        ({"args": ["debug"]}, "not 'debug'"),
        ({"args": ["retry"]}, "not 'retry'"),
        ({"args": ["--select", "lims"]}, "not '--select'"),
        ({"args": []}, "not nothing"),
        ({"args": ""}, "not nothing"),
        ({"args": "build --vars '{\"a\": 1}"}, "Can't split args: No closing quotation"),
        ({"args": ["build", 1]}, "args must be a list of strings, or a string"),
        ({"args": {"select": "lims"}}, "args must be a list of strings, or a string"),
        ([], "must be a JSON object"),
    ],
)
def test_invalid_requests(request_json, message):
    with pytest.raises(RequestError, match=re.escape(message)):
        parse_request(json.dumps(request_json))


def test_not_json():
    with pytest.raises(RequestError, match="isn't valid JSON"):
        parse_request("not json")
