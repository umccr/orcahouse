import os
import json
import datetime
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
from os.path import join
import utils


# Get the secret name from environment variables
DB_SECRET_NAME = os.environ["DB_SECRET_NAME"]

DB_SCHEMA = "psa"
TABLE_NAME = "event__variant_monitoring_result"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "VariantMonitoringResult"
EVENT_SOURCE = "orcabus.variantmonitoring"
RECORD_SOURCE = f"{EVENT_SOURCE}:{DETAIL_TYPE}"

# Prevent inserts of the same event record multiple times
SQL_INSERT = f"INSERT INTO {TABLE} (%s) SELECT %s WHERE NOT EXISTS (SELECT 1 FROM {TABLE} WHERE event_id = %s);"

# DB connection
session = boto3.session.Session()
secretsmanager_client = boto3.client("secretsmanager")
DB_CREDENTIALS = utils.get_secret(DB_SECRET_NAME, secretsmanager_client)
DB_CONNECTION = utils.get_db_connection(DB_CREDENTIALS)


def handler(event, context):
    print("Lambda function invoked!")
    print(f"Event: {event}")
    try:
        data = parse_event(event)
        utils.push_to_db(DB_CONNECTION, SQL_INSERT, data)

        print("Returning results.")
        return {
            'statusCode': 200,
        }

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

    # make sure we have an expected event type
    if detail_type != DETAIL_TYPE:
        raise ValueError(f"Invalid event type. Expected '{DETAIL_TYPE}' but got '{detail_type}'")
    if event_source != EVENT_SOURCE:
        raise ValueError(f"Invalid event source. Expected '{EVENT_SOURCE}' but got '{event_source}'")

    event_id = event.get('id')
    event_time = event.get('time')
    detail = event.get('detail')

    data = {
        "event_id": event_id,
        "event_time": event_time,
        "orcabus_id": str(detail.get('id', "")),
        "schema_version": str(detail.get('version', "")),
        "timestamp": str(detail.get('timestamp', "")),
        "portal_run_id": str(detail.get('portalRunId', "")),
        "workflow_run_orcabus_id": str(detail.get('workflowRunOrcabusId', "")),
        "workflow_name": str(detail.get('workflowName', "")),
        "workflow_version": str(detail.get('workflowVersion', "")),
        "library_id": str(detail.get('libraryId', "")),
        "library_orcabus_id": str(detail.get('libraryOrcabusId', "")),
        "subject_id": str(detail.get('subjectId', "")),
        "individual_id": str(detail.get('individualId', "")),
        "giab_id": str(detail.get('giabId', "")),
        "analysis_name": str(detail.get('analysisName', "")),
        "output_uri": str(detail.get('outputUri', "")),
        "monitoring_sites": json.dumps(detail.get('monitoringSites', [])),
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {data}")

    return data


def test_case():
    # Execute example query
    print("Executing query...")
    with DB_CONNECTION:
        with DB_CONNECTION.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(f"SELECT * FROM {TABLE_NAME} LIMIT 5")
            results = cur.fetchall()

    # Convert results to JSON-serializable format
    print("Query executed successfully!")
    results_list = [dict(row) for row in results]
    print(f"Results: {results_list}")
