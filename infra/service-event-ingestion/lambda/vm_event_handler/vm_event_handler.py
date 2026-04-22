import os
import datetime
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
import utils


DB_SECRET_NAME = os.environ["DB_SECRET_NAME"]

DB_SCHEMA = "psa"
TABLE_NAME = "event__variant_monitoring_result"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "VariantMonitoringResult"
EVENT_SOURCE = "orcabus.variantmonitoring"
RECORD_SOURCE = f"{EVENT_SOURCE}:{DETAIL_TYPE}"

SQL_INSERT = (
    f"INSERT INTO {TABLE} ({{columns}}) VALUES ({{placeholders}}) "
    f"ON CONFLICT (portal_run_id, chrom, pos, ref, alt) DO NOTHING"
)

session = boto3.session.Session()
secretsmanager_client = boto3.client("secretsmanager")
DB_CREDENTIALS = utils.get_secret(DB_SECRET_NAME, secretsmanager_client)
DB_CONNECTION = utils.get_db_connection(DB_CREDENTIALS)


def handler(event, context):
    print("Lambda function invoked!")
    print(f"Event: {event}")
    try:
        rows = parse_event(event)
        for row in rows:
            _insert_row(DB_CONNECTION, row)

        print("Returning results.")
        return {'statusCode': 200}

    except Exception as e:
        print(f"An error occurred: {e}")
        raise e


def parse_event(event):
    """
    Example VariantMonitoringResult event:
    {
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
                    "variant_emitted": true
                }
            ]
        }
    }
    """
    print("Parsing event...")
    detail_type = event.get('detail-type')
    event_source = event.get('source')

    if detail_type != DETAIL_TYPE:
        raise ValueError(f"Invalid event type. Expected '{DETAIL_TYPE}' but got '{detail_type}'")
    if event_source != EVENT_SOURCE:
        raise ValueError(f"Invalid event source. Expected '{EVENT_SOURCE}' but got '{event_source}'")

    event_id = event.get('id')
    event_time = event.get('time')
    detail = event.get('detail')

    base = {
        "event_id": event_id,
        "event_time": event_time,
        "portal_run_id": str(detail.get('portalRunId', "")),
        "library_id": str(detail.get('libraryId', "")),
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }

    sites = detail.get('monitoringSites', [])
    if not sites:
        print("Warning: monitoringSites is empty, skipping insert.")
        return []

    rows = []
    for site in sites:
        rows.append({
            **base,
            "chrom": site.get('chrom'),
            "pos": site.get('pos'),
            "ref": site.get('ref'),
            "alt": site.get('alt'),
            "dp": site.get('dp'),
            "af": site.get('af'),
            "filter_status": site.get('filter_status'),
            "variant_emitted": site.get('variant_emitted'),
        })

    print(f"Extracted {len(rows)} site rows")
    return rows


def _insert_row(conn, data):
    columns = ", ".join(data.keys())
    placeholders = ", ".join(["%s"] * len(data))
    sql = SQL_INSERT.format(columns=columns, placeholders=placeholders)
    with conn:
        with conn.cursor() as cur:
            print(f"SQL: {cur.mogrify(sql, list(data.values()))}")
            cur.execute(sql, list(data.values()))
