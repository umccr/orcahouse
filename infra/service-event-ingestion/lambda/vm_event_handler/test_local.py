"""
Local integration test for vm_event_handler.
Requires the dev Postgres to be running: cd dev && make up && make psa
"""
import sys
import os
import math
from unittest.mock import MagicMock, patch

os.environ.setdefault("DB_SECRET_NAME", "test-secret")

_mock_utils = MagicMock()
_mock_utils.get_secret.return_value = {}
_mock_utils.get_db_connection.return_value = MagicMock()

with patch.dict("sys.modules", {"utils": _mock_utils}), \
     patch("boto3.client", return_value=MagicMock()), \
     patch("boto3.session.Session", return_value=MagicMock()):
    sys.path.insert(0, os.path.dirname(__file__))
    import vm_event_handler

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
    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    assert len(rows) == 2
    assert rows[0]["chrom"] == "chr1"
    assert rows[0]["pos"] == 100000
    assert math.isclose(rows[0]["af"], 0.489)
    assert rows[0]["variant_emitted"] is True
    assert rows[1]["chrom"] == "chr7"
    assert rows[1]["variant_emitted"] is False
    print("  PASS test_parse_event")


def test_db_insert():
    conn = get_conn()
    cleanup(conn, SAMPLE_EVENT["id"])

    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    for row in rows:
        vm_event_handler._insert_row(conn, row)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT * FROM psa.event__variant_monitoring_result WHERE event_id = %s ORDER BY chrom",
            (SAMPLE_EVENT["id"],),
        )
        result = cur.fetchall()

    assert len(result) == 2
    assert result[0]["chrom"] == "chr1"
    assert result[0]["pos"] == 100000
    assert result[0]["variant_emitted"] is True
    assert result[0]["portal_run_id"] == "20250416abcdef01"
    assert result[0]["library_id"] == "L2401538"
    assert result[0]["record_source"] == "orcabus.variantmonitoring:VariantMonitoringResult"
    assert result[1]["chrom"] == "chr7"
    assert result[1]["variant_emitted"] is False
    print("  PASS test_db_insert")
    conn.close()


def test_duplicate_insert():
    conn = get_conn()
    cleanup(conn, SAMPLE_EVENT["id"])

    rows = vm_event_handler.parse_event(SAMPLE_EVENT)
    for row in rows:
        vm_event_handler._insert_row(conn, row)
    for row in rows:
        vm_event_handler._insert_row(conn, row)

    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM psa.event__variant_monitoring_result WHERE event_id = %s",
            (SAMPLE_EVENT["id"],),
        )
        count = cur.fetchone()[0]

    assert count == 2, f"Expected 2 rows (one per site) but got {count}"
    print("  PASS test_duplicate_insert")
    cleanup(conn, SAMPLE_EVENT["id"])
    conn.close()


def test_two_events_same_site_coordinates():
    event_a = {**SAMPLE_EVENT, "id": "test-event-id-local-002"}
    event_b = {
        **SAMPLE_EVENT,
        "id": "test-event-id-local-003",
        "detail": {**SAMPLE_EVENT["detail"], "portalRunId": "20250417abcdef02"},  # pragma: allowlist secret
    }
    conn = get_conn()
    cleanup(conn, event_a["id"])
    cleanup(conn, event_b["id"])

    for row in vm_event_handler.parse_event(event_a):
        vm_event_handler._insert_row(conn, row)
    for row in vm_event_handler.parse_event(event_b):
        vm_event_handler._insert_row(conn, row)

    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM psa.event__variant_monitoring_result WHERE event_id IN (%s, %s)",
            (event_a["id"], event_b["id"]),
        )
        count = cur.fetchone()[0]

    assert count == 4, f"Expected 4 rows (2 sites x 2 events) but got {count}"
    print("  PASS test_two_events_same_site_coordinates")
    cleanup(conn, event_a["id"])
    cleanup(conn, event_b["id"])
    conn.close()


def test_site_with_missing_optional_fields():
    event = {
        **SAMPLE_EVENT,
        "id": "test-event-id-local-004",
        "detail": {
            **SAMPLE_EVENT["detail"],
            "monitoringSites": [
                {"chrom": "chr1", "pos": 100000, "ref": "A", "alt": "T", "variant_emitted": False},
            ],
        },
    }
    conn = get_conn()
    cleanup(conn, event["id"])

    rows = vm_event_handler.parse_event(event)
    for row in rows:
        vm_event_handler._insert_row(conn, row)

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT * FROM psa.event__variant_monitoring_result WHERE event_id = %s",
            (event["id"],),
        )
        result = cur.fetchone()

    assert result["chrom"] == "chr1"
    assert result["dp"] is None
    assert result["af"] is None
    print("  PASS test_site_with_missing_optional_fields")
    cleanup(conn, event["id"])
    conn.close()


def test_empty_monitoring_sites_inserts_nothing():
    event = {
        **SAMPLE_EVENT,
        "id": "test-event-id-local-005",
        "detail": {**SAMPLE_EVENT["detail"], "monitoringSites": []},
    }
    conn = get_conn()
    cleanup(conn, event["id"])

    rows = vm_event_handler.parse_event(event)
    for row in rows:
        vm_event_handler._insert_row(conn, row)

    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM psa.event__variant_monitoring_result WHERE event_id = %s",
            (event["id"],),
        )
        count = cur.fetchone()[0]

    assert count == 0, f"Expected 0 rows for empty sites but got {count}"
    print("  PASS test_empty_monitoring_sites_inserts_nothing")
    conn.close()


if __name__ == "__main__":
    print("Running local integration tests for vm_event_handler...")
    test_parse_event()
    test_db_insert()
    test_duplicate_insert()
    test_two_events_same_site_coordinates()
    test_site_with_missing_optional_fields()
    test_empty_monitoring_sites_inserts_nothing()
    print("All tests passed.")
