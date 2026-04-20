"""
Local integration test for vm_event_handler.
Requires the dev Postgres to be running: cd dev && make up && make psa
"""
import json
import sys
import os
from unittest.mock import MagicMock, patch

# Patch module-level AWS/DB calls so the import doesn't fail without AWS
os.environ.setdefault("DB_SECRET_NAME", "test-secret")

_mock_utils = MagicMock()
_mock_utils.get_secret.return_value = {}
_mock_utils.get_db_connection.return_value = MagicMock()

with patch.dict("sys.modules", {"utils": _mock_utils}), \
     patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.session.Session", return_value=MagicMock()):
    sys.path.insert(0, os.path.dirname(__file__))
    import vm_event_handler

import psycopg2
from psycopg2.extras import RealDictCursor

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../utils"))
import utils as real_utils

DB_CREDENTIALS = {
    "host": "localhost",
    "port": 5432,
    "dbname": "orcavault",
    "username": "dev",
    "password": "dev",  # pragma: allowlist-secret
}

SAMPLE_EVENT = {
    "version": "0",
    "id": "test-event-id-local-001",
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


def get_conn():
    return real_utils.get_db_connection(DB_CREDENTIALS)


def cleanup(conn, event_id):
    with conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM psa.event__variant_monitoring_result WHERE event_id = %s",
                (event_id,),
            )


def test_parse_event():
    data = vm_event_handler.parse_event(SAMPLE_EVENT)
    assert data["event_id"] == "test-event-id-local-001"
    assert data["library_id"] == "L2401538"
    assert data["workflow_name"] == "dragen-wgts-dna"
    sites = json.loads(data["monitoring_sites"])
    assert sites[0]["chrom"] == "chr1"
    print("  PASS test_parse_event")


def test_db_insert():
    conn = get_conn()
    cleanup(conn, SAMPLE_EVENT["id"])

    data = vm_event_handler.parse_event(SAMPLE_EVENT)
    real_utils.push_to_db(conn, vm_event_handler.SQL_INSERT, data)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT * FROM psa.event__variant_monitoring_result WHERE event_id = %s",
            (SAMPLE_EVENT["id"],),
        )
        rows = cur.fetchall()

    assert len(rows) == 1
    row = rows[0]
    assert row["library_id"] == "L2401538"
    assert row["record_source"] == "orcabus.variantmonitoring:VariantMonitoringResult"
    sites = row["monitoring_sites"]  # jsonb is already deserialised by psycopg2
    assert sites[0]["chrom"] == "chr1"
    print("  PASS test_db_insert")
    conn.close()


def test_duplicate_insert():
    conn = get_conn()
    cleanup(conn, SAMPLE_EVENT["id"])

    data = vm_event_handler.parse_event(SAMPLE_EVENT)
    real_utils.push_to_db(conn, vm_event_handler.SQL_INSERT, data)
    real_utils.push_to_db(conn, vm_event_handler.SQL_INSERT, data)

    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM psa.event__variant_monitoring_result WHERE event_id = %s",
            (SAMPLE_EVENT["id"],),
        )
        count = cur.fetchone()[0]

    assert count == 1, f"Expected 1 row but got {count}"
    print("  PASS test_duplicate_insert")
    cleanup(conn, SAMPLE_EVENT["id"])
    conn.close()


if __name__ == "__main__":
    print("Running local integration tests for vm_event_handler...")
    test_parse_event()
    test_db_insert()
    test_duplicate_insert()
    print("All tests passed.")
