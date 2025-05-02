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
TABLE_NAME = "event__sequence_run_state_change"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "SequenceRunStateChange"
EVENT_SOURCE = "orcabus.sequencerunmanager"
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
            "statusCode": 200,
        }

    except Exception as e:
        print(f"An error occurred: {e}")
        raise e


def parse_event(event):
    # Parse the event and extract the SRM State Change details
    """
    Example SequenceRunStateChange event:
    {
        "version": "0",
        "id": "261d80cd-7c49-9856-7803-1b9152a3bd9f",
        "detail-type": "SequenceRunStateChange",
        "source": "orcabus.sequencerunmanager",
        "account": "472057503814",
        "time": "2025-03-29T20:27:27Z",
        "region": "ap-southeast-2",
        "resources": [],
        "detail": {
            "endTime": "2025-03-29T20:27:10.797085+00:00",
            "id": "seq.01JQDAHDFQAXT312YSV2G1EY17",
            "instrumentRunId": "250328_A01052_0257_BHFFVFDSXF",
            "runDataUri": "gds://bssh.24734fa0debe3f9f8b9221244f46822c",
            "runFolderPath": "",
            "runVolumeName": "bssh.24734fa0debe3f9f8b9221244f46822c",
            "sampleSheetName": "sampleSheet_v2.csv",
            "startTime": "2025-03-28T02:50:31.435111+00:00",
            "status": "SUCCEEDED"
        }
    }
    """
    print("Parsing event...")
    detail_type = event.get("detail-type")
    event_source = event.get("source")

    # make sure we have an expected event type
    if detail_type != DETAIL_TYPE:
        raise ValueError(
            f"Invalid event type. Expected '{DETAIL_TYPE}' but got '{detail_type}'"
        )
    if event_source != EVENT_SOURCE:
        raise ValueError(
            f"Invalid event source. Expected '{EVENT_SOURCE}' but got '{event_source}'"
        )

    event_id = event.get("id")
    event_time = event.get("time")
    detail = event.get("detail")

    orcabus_id = detail.get("id")
    instrument_run_id = detail.get("instrumentRunId")
    status = detail.get("status")
    start_time = detail.get("startTime")
    end_time = detail.get("endTime", "")
    ss_name = detail.get("sampleSheetName", "")

    srsc_data = {
        "event_id": event_id,
        "event_time": event_time,
        "orcabus_id": orcabus_id,
        "status": status,
        "instrument_run_id": instrument_run_id,
        "start_time": start_time,
        "end_time": end_time,
        "samplesheet_name": ss_name,
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {srsc_data}")

    return srsc_data


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
