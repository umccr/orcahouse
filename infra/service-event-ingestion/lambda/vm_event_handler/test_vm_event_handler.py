import sys
import os
from unittest.mock import MagicMock, patch

os.environ.setdefault("DB_SECRET_NAME", "test-secret")

with patch.dict("sys.modules", {"utils": MagicMock()}), \
     patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.session.Session", return_value=MagicMock()):
    sys.path.insert(0, os.path.dirname(__file__))
    import vm_event_handler

import pytest

SAMPLE_EVENT = {
    "version": "0",
    "id": "abc123",
    "detail-type": "VariantMonitoringResult",
    "source": "orcabus.variantmonitoring",
    "account": "472057503814",
    "time": "2025-04-16T10:00:00Z",
    "region": "ap-southeast-2",
    "resources": [],
    "detail": {
        "id": "d41d8cd98f00b204e9800998ecf8427e",  # pragma: allowlist secret
        "version": "0.1.0",
        "timestamp": "2025-04-16T10:00:00+00:00",
        "portalRunId": "20250416abcdef01",  # pragma: allowlist secret
        "workflowRunOrcabusId": "wfr.01JXXXXX",
        "workflowName": "dragen-wgts-dna",
        "workflowVersion": "4.3.6",
        "libraryId": "L2401538",
        "libraryOrcabusId": "lib.01JXXXXX",
        "subjectId": "SBJ00001",
        "individualId": "NA12878",
        "giabId": "HG001",
        "analysisName": "umccr--automated--dragen-wgts-dna--4-3-6--20250416abcdef01",
        "outputUri": "s3://pipeline-dev-cache-xxx/byob-icav2/.../dragen-wgts-dna/20250416abcdef01/",
        "monitoringSites": [
            {"chrom": "chr1", "pos": 100000, "ref": "A", "alt": "T", "dp": 45, "af": 0.489, "filter_status": "PASS", "variant_emitted": True},
            {"chrom": "chr7", "pos": 55259515, "ref": "G", "alt": "A", "dp": 38, "af": 0.012, "filter_status": "PASS", "variant_emitted": False},
        ],
    },
}


def test_parse_event_returns_one_row_per_site():
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    assert len(rows) == 2


def test_parse_event_only_contains_expected_columns():
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    expected_keys = {
        "event_id", "event_time", "portal_run_id", "library_id",
        "chrom", "pos", "ref", "alt", "dp", "af",
        "filter_status", "variant_emitted", "load_datetime", "record_source",
    }
    assert set(rows[0].keys()) == expected_keys


def test_parse_event_event_fields_repeated_on_every_row():
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    for row in rows:
        assert row["event_id"] == "abc123"
        assert row["portal_run_id"] == "20250416abcdef01"
        assert row["library_id"] == "L2401538"
        assert row["record_source"] == "orcabus.variantmonitoring:VariantMonitoringResult"


def test_parse_event_site_fields_correctly_mapped():
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    assert rows[0]["chrom"] == "chr1"
    assert rows[0]["pos"] == 100000
    assert rows[0]["af"] == pytest.approx(0.489)
    assert rows[0]["variant_emitted"] is True
    assert rows[1]["chrom"] == "chr7"
    assert rows[1]["variant_emitted"] is False


def test_parse_event_typed_values_not_cast_to_string():
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    assert isinstance(rows[0]["pos"], int)
    assert isinstance(rows[0]["af"], float)
    assert isinstance(rows[0]["variant_emitted"], bool)


def test_parse_event_empty_monitoring_sites_returns_no_rows():
    event = {**SAMPLE_EVENT, "detail": {**SAMPLE_EVENT["detail"], "monitoringSites": []}}
    rows = vm_event_handler.parse_event(event)
    assert rows == []


def test_parse_event_wrong_detail_type():
    event = {**SAMPLE_EVENT, "detail-type": "SomethingElse"}
    with pytest.raises(ValueError, match="Invalid event type"):
        vm_event_handler.parse_event(event)


def test_parse_event_wrong_source():
    event = {**SAMPLE_EVENT, "source": "orcabus.other"}
    with pytest.raises(ValueError, match="Invalid event source"):
        vm_event_handler.parse_event(event)
