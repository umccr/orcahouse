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
TABLE_NAME = "event__metadata_state_change_library"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "MetadataStateChange"
EVENT_SOURCE = "orcabus.metadatamanager"
SUB_TYPE = "library"
RECORD_SOURCE = f"{EVENT_SOURCE}:{DETAIL_TYPE}:{SUB_TYPE}"

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
    # Parse the event and extract the Metadata State Change details for the Library record
    """
    Example MetadataStateChange event:
    {
        "version": "0",
        "id": "f7dd6b99-d7cc-ca61-9577-7f7a54f60967",
        "detail-type": "MetadataStateChange",
        "source": "orcabus.metadatamanager",
        "account": "472057503814",
        "time": "2025-05-05T05:11:44Z",
        "region": "ap-southeast-2",
        "resources": [],
        "detail": {
            "action": "UPDATE",
            "model": "LIBRARY",
            "refId": "lib.01JBMTFP4TQZ6MMTHE9ASJNZK7",
            "data": {
                "orcabusId": "lib.01JBMTFP4TQZ6MMTHE9ASJNZK7",
                "libraryId": "L1900827",
                "phenotype": "negative-control",
                "workflow": "control",
                "quality": "good",
                "type": "exome",
                "assay": "AgSsCRE",
                "coverage": 0.1,
                "overrideCycles": "Y100N51;I8N2;U10;Y100N51",
                "sample": "smp.01JBMTFP4ENWHC8NMGEMWZ4WHE",
                "subject": "sbj.01JBMTFKRP3XNJ7BBW28R5NXTG"
            }
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

    event_model = detail.get('model', "")
    if not event_model.lower() = SUB_TYPE.lower():
        raise ValueError(
            f"Invalid event model type. Expected '{SUB_TYPE}' but got '{event_model}'"
        )

    orcabus_id = detail.get("refId")  # TODO: check against 'data.orcabusId' ?
    event_action = detail.get("action")
    event_data = detail.get("data")
    if not event_data:
        raise ValueError("Expected event payload data, but got nothing.")

    library_id = event_data.get("libraryId")
    phenotype = event_data.get("phenotype")
    workflow = event_data.get("workflow")
    quality = event_data.get("quality")
    lib_type = event_data.get("type")
    assay = event_data.get("assay")
    coverage = event_data.get("coverage")
    overrideCycles = event_data.get("overrideCycles")
    sample_id = event_data.get("sample")
    subject_id = event_data.get("subject")

    mm_data = {
        "event_id": event_id,
        "event_time": event_time,
        "orcabus_id": orcabus_id,
        "action": event_action,
        "library_id": library_id,
        "phenotype": phenotype,
        "workflow": workflow,
        "quality": quality,
        "type": lib_type,
        "assay": assay,
        "coverage": coverage,
        "overrideCycles": overrideCycles,
        "sample_orcabus_id": sample_id,
        "subject_orcabus_id": subject_id,
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {mm_data}")

    return mm_data


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
