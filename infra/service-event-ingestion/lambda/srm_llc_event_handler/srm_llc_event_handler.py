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
TABLE_NAME = "event__sequence_run_library_linking_change"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "SequenceRunLibraryLinkingChange"
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
    # TODO: check against production version
    """
    Example SequenceRunLibraryLinkingChange event:
    {
        "version": "0",
        "id": "3384bb0b-04d3-bdfb-2837-71c725404aed",
        "detail-type": "SequenceRunLibraryLinkingChange",
        "source": "orcabus.sequencerunmanager",
        "account": "000000000000",
        "time": "2025-03-00T00:00:00Z",
        "region": "ap-southeast-2",
        "resources": [],
        "detail": {
            "instrumentRunId": "250328_A01052_0258_AHFGM7DSXF",
            "sequenceRunId": "r.dwkNXIeo5kKjNsBfOpnaFA", // fake sequence run id
            "sequenceOrcabusId": "seq.01JQDAHGFJCARHF2XJ93YR6V8G", // orcabusid for the sequence run (fake run)
            "timeStamp": "2025-03-01T00:00:00.000000+00:00",
            "linkedLibrary": [
                "L2000000",
                "L2000001",
                "L2000002"
            ]
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

    orcabus_id = str(detail.get("sequenceOrcabusId", ""))
    instrument_run_id = str(detail.get("instrumentRunId", ""))
    sequence_run_id = str(detail.get("sequenceRunId", ""))
    timestamp = str(detail.get("timeStamp", ""))
    libraries = detail.get("linkedLibrary", {})
    


    srllc_data = {
        "event_id": event_id,
        "event_time": event_time,
        "orcabus_id": orcabus_id,
        "instrument_run_id": instrument_run_id,
        "sequence_run_id": sequence_run_id,
        "timestamp": timestamp,
        "libraries": json.dumps(libraries),
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {srllc_data}")

    return srllc_data


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
