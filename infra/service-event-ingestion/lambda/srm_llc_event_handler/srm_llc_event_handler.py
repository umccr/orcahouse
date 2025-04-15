import os
import json
import datetime
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.extensions import AsIs
from os.path import join


TABLE_NAME = "psa.sequence_run_library_change_events"
SRLLC_DETAIL_TYPE = "SequenceRunLibraryLinkingChange"
SRLLC_EVENT_SOURCE = "orcabus.sequencerunmanager"
RECORD_SOURCE = f"{SRLLC_EVENT_SOURCE}:{SRLLC_DETAIL_TYPE}"
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
        srllc_data = parse_event(event)
        push_to_db(srllc_data)

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
    if detail_type != SRLLC_DETAIL_TYPE:
        raise ValueError(
            f"Invalid event type. Expected '{SRLLC_DETAIL_TYPE}' but got '{detail_type}'"
        )
    if event_source != SRLLC_EVENT_SOURCE:
        raise ValueError(
            f"Invalid event source. Expected '{SRLLC_EVENT_SOURCE}' but got '{event_source}'"
        )

    event_id = event.get("id")
    event_time = event.get("time")
    detail = event.get("detail")

    seq_id = detail.get("sequenceOrcabusId")
    instrument_run_id = detail.get("instrumentRunId")
    sequence_run_id = detail.get("sequenceRunId")
    timestamp = detail.get("timeStamp")
    libraries = detail.get("linkedLibrary")
    


    srllc_data = {
        "event_id": event_id,
        "event_time": event_time,
        "sequence_id": seq_id,
        "instrument_run_id": instrument_run_id,
        "sequence_run_id": sequence_run_id,
        "timestamp": timestamp,
        "libraries": json.dumps(libraries),
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE,
    }
    print(f"Extracted data: {srllc_data}")

    return srllc_data


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
