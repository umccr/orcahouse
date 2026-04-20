import json
import sys
import os
from unittest.mock import MagicMock, patch

# Patch module-level AWS/DB calls before import
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
        "id": "d41d8cd98f00b204e9800998ecf8427e",
        "version": "0.1.0",
        "timestamp": "2025-04-16T10:00:00+00:00",
        "portalRunId": "20250416abcdef01",
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
            {
                "chrom": "chr1",
                "pos": 100000,
                "ref": "A",
                "alt": "T",
                "dp": 45,
                "af": 0.489,
                "filter_status": "PASS",
                "variant_emitted": True,
            }
        ],
    },
}


def test_parse_event_happy_path():
    data = vm_event_handler.parse_event(SAMPLE_EVENT)

    assert data["event_id"] == "abc123"
    assert data["event_time"] == "2025-04-16T10:00:00Z"
    assert data["orcabus_id"] == "d41d8cd98f00b204e9800998ecf8427e"
    assert data["schema_version"] == "0.1.0"
    assert data["timestamp"] == "2025-04-16T10:00:00+00:00"
    assert data["portal_run_id"] == "20250416abcdef01"
    assert data["workflow_run_orcabus_id"] == "wfr.01JXXXXX"
    assert data["workflow_name"] == "dragen-wgts-dna"
    assert data["workflow_version"] == "4.3.6"
    assert data["library_id"] == "L2401538"
    assert data["library_orcabus_id"] == "lib.01JXXXXX"
    assert data["subject_id"] == "SBJ00001"
    assert data["individual_id"] == "NA12878"
    assert data["giab_id"] == "HG001"
    assert data["analysis_name"] == "umccr--automated--dragen-wgts-dna--4-3-6--20250416abcdef01"
    assert data["output_uri"].startswith("s3://")
    assert data["record_source"] == "orcabus.variantmonitoring:VariantMonitoringResult"


def test_parse_event_monitoring_sites_serialised_as_json():
    data = vm_event_handler.parse_event(SAMPLE_EVENT)
    sites = json.loads(data["monitoring_sites"])
    assert isinstance(sites, list)
    assert sites[0]["chrom"] == "chr1"
    assert sites[0]["af"] == 0.489


def test_parse_event_empty_monitoring_sites():
    event = {**SAMPLE_EVENT, "detail": {**SAMPLE_EVENT["detail"], "monitoringSites": []}}
    data = vm_event_handler.parse_event(event)
    assert json.loads(data["monitoring_sites"]) == []


def test_parse_event_wrong_detail_type():
    event = {**SAMPLE_EVENT, "detail-type": "SomethingElse"}
    with pytest.raises(ValueError, match="Invalid event type"):
        vm_event_handler.parse_event(event)


def test_parse_event_wrong_source():
    event = {**SAMPLE_EVENT, "source": "orcabus.other"}
    with pytest.raises(ValueError, match="Invalid event source"):
        vm_event_handler.parse_event(event)


def test_parse_event_missing_optional_fields():
    detail = {
        "id": "minimalid",
        "version": "0.1.0",
    }
    event = {**SAMPLE_EVENT, "detail": detail}
    data = vm_event_handler.parse_event(event)
    assert data["orcabus_id"] == "minimalid"
    assert data["portal_run_id"] == ""
    assert data["monitoring_sites"] == "[]"
