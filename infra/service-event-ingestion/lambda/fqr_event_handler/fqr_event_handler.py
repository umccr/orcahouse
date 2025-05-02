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
TABLE_NAME = "event__fastq_list_row_state_change"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "FastqListRowStateChange"
EVENT_SOURCE = "orcabus.fastqmanager"
RECORD_SOURCE = f"{EVENT_SOURCE}:{DETAIL_TYPE}"

# Prevent inserts of the same event record multiple times
# TODO: consider hashing the event values and only insert records that differ
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
    # Parse the event and extract the FQR code
    # This is a placeholder function and should be implemented based on the actual event structure
    """
    Example FastqListRowStateChange event:
    {
        "version": "0",
        "id": "8ab8bc9e-aa0a-4bdd-4aa3-b16031df2205",
        "detail-type": "FastqListRowStateChange",
        "source": "orcabus.fastqmanager",
        "account": "843407916570",
        "time": "2025-04-15T23:40:29Z",
        "region": "ap-southeast-2",
        "resources": [],
        "detail": {
            "status": "QC_UPDATED",
            "id": "fqr.01JQ3BEKS05C74XWT5PYED6KV5",
            "fastqSetId": "fqs.01JQ3BEKVEQGYVQNDVP4YQA7ZQ",
            "index": "CCGCGGTT+CTAGCGCT",
            "lane": 2,
            "instrumentRunId": "241024_A00130_0336_BHW7MVDSXC",
            "library": {
                "orcabusId": "lib.01JBB5Y3901PA0X3FBMWBKYNMB",
                "libraryId": "L2401538"
            },
            "platform": "Illumina",
            "center": "UMCCR",
            "date": "2024-10-24T00:00:00",
            "readSet": {
                "r1": {
                    "gzipCompressionSizeInBytes": null,
                    "rawMd5sum": null,
                    "ingestId": "0195c5fa-cd5f-74f3-ade9-39a6ab6d1fec"
                },
                "r2": {
                    "gzipCompressionSizeInBytes": null,
                    "rawMd5sum": null,
                    "ingestId": "0195c5fa-d2de-7bd0-bcc5-6bd438f6927c"
                },
                "compressionFormat": "ORA"
            },
            "qc": {
                "insertSizeEstimate": 286,
                "rawWgsCoverageEstimate": 61.65,
                "r1Q20Fraction": 0.98,
                "r2Q20Fraction": 0.96,
                "r1GcFraction": 0.4,
                "r2GcFraction": 0.41,
                "duplicationFractionEstimate": 0.25
            },
            "readCount": 632745128,
            "baseCountEst": 1265490256,
            "isValid": true,
            "ntsm": null
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

    orcabus_id = detail.get('id')
    status = detail.get('status', "")
    instrument_run_id = detail.get('instrumentRunId', "")
    library = detail.get('library').get('libraryId', "")
    lane = detail.get('lane', "")
    is_valid = detail.get('isValid', "")
    index = detail.get('index', "")

    readset = detail.get('readSet')
    readset_r1 = ""
    readset_r2 = ""
    if readset:
        readset_r1 = readset.get('r1').get('ingestId', "")
        readset_r2 = readset.get('r2').get('ingestId', "")

    fqr_data = {
        "event_id": event_id,
        "event_time": event_time,
        "orcabus_id": orcabus_id,
        "status": status,
        "instrument_run_id": instrument_run_id,
        "library": library,
        "lane": str(lane),
        "index": index,
        "is_valid": str(is_valid),
        "readset_r1": readset_r1,
        "readset_r2": readset_r2,
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE
    }
    print(f"Extracted data: {fqr_data}")

    return fqr_data


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
