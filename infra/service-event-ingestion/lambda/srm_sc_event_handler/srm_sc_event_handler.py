import os
import json
import datetime
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.extensions import AsIs
from os.path import join


TABLE_NAME = "psa.sequence_run_state_change_events"
SRSC_DETAIL_TYPE = "SequenceRunStateChange"
SRSC_EVENT_SOURCE = "orcabus.sequencerunmanager"
RECORD_SOURCE = f"{SRSC_EVENT_SOURCE}:{SRSC_DETAIL_TYPE}"
# Get the secret name from environment variables
DB_SECRET_NAME = os.environ["DB_SECRET_NAME"]

# SQL_INSERT = "INSERT INTO psa.fastq_list_row_change_events (%s) VALUES %s;"
# Prevent inserts of the same event record multiple times
# TODO: consider hashing the event values and only insert records that differ
SQL_INSERT = f"INSERT INTO {TABLE_NAME} (%s) SELECT %s WHERE NOT EXISTS (SELECT 1 FROM {TABLE_NAME} WHERE event_id = %s);"


# function to retrieve DB credetials
def get_secret(secret_name):
    """
    Retrieve secret from AWS Secrets Manager
    """
    print("Retrieving DB credentials from Secrets Manager...")
    session = boto3.session.Session()
    client = boto3.client("secretsmanager")

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise e
    else:
        if "SecretString" in get_secret_value_response:
            secret = json.loads(get_secret_value_response["SecretString"])
            return secret
        else:
            print("Secret not found!")


# function to establish DB connection
def get_db_connection(credentials):
    print("Establishing connection to database...")
    username = credentials.get("username")
    password = credentials.get("password")
    host = credentials.get("host")
    port = credentials.get("port")
    dbname = credentials.get("dbname")
    print("Connecting to the database...")

    conn = psycopg2.connect(
        host=host, database=dbname, user=username, password=password, port=port
    )
    if conn:
        print("Connection established!")
    else:
        print("Connection failed!")
    return conn


DB_CREDENTIALS = get_secret(DB_SECRET_NAME)
DB_CONNECTION = get_db_connection(DB_CREDENTIALS)


def handler(event, context):
    print("Lambda function invoked!")
    print(f"Event: {event}")
    try:
        srsc_data = parse_event(event)
        push_to_db(srsc_data)

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
    if detail_type != SRSC_DETAIL_TYPE:
        raise ValueError(
            f"Invalid event type. Expected '{SRSC_DETAIL_TYPE}' but got '{detail_type}'"
        )
    if event_source != SRSC_EVENT_SOURCE:
        raise ValueError(
            f"Invalid event source. Expected '{SRSC_EVENT_SOURCE}' but got '{event_source}'"
        )

    event_id = event.get("id")
    event_time = event.get("time")
    detail = event.get("detail")

    seq_id = detail.get("id")
    instrument_run_id = detail.get("instrumentRunId")
    status = detail.get("status")
    start_time = detail.get("startTime")
    end_time = detail.get("endTime")
    ss_name = detail.get("sampleSheetName")


    srsc_data = {
        "event_id": event_id,
        "event_time": event_time,
        "sequence_id": seq_id,
        "instrument_run_id": instrument_run_id,
        "status": status,
        "start_time": start_time,
        "end_time": end_time,
        "sample_sheet_name": ss_name,
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {srsc_data}")

    return srsc_data


def push_to_db(data):
    print("Pushing data to database...")
    with DB_CONNECTION:
        with DB_CONNECTION.cursor() as cur:
            values = str(tuple(data.values()))[1:-1]  # strip off tuple brackets
            sql = cur.mogrify(
                SQL_INSERT,
                (AsIs(",".join(data.keys())), AsIs(values), data["event_id"]),
            )
            print(f"SQL to execute: {sql}")
            # cur.execute(sql)

    print("Data pushed to database!")


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
