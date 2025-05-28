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
TABLE_NAME = "event__workflow_run_state_change"
TABLE = f"{DB_SCHEMA}.{TABLE_NAME}"
DETAIL_TYPE = "WorkflowRunStateChange"
EVENT_SOURCE = "orcabus.workflowmanager"
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
    # Parse the event and extract the event data
    """
    Example WorkflowRunStateChange event:
	{
		"version": "0",
		"id": "dca7ec80-5c2b-8977-1ef4-4466364793dc",
		"detail-type": "WorkflowRunStateChange",
		"source": "orcabus.manual",
		"account": "472057503814",
		"time": "2025-04-25T13:00:45Z",
		"region": "ap-southeast-2",
		"resources": [],
		"detail": {
			"portalRunId": "20250424109aedfe",  # pragma: allowlist secret
			"timestamp": "2025-04-24T21:38:05+00:00",
			"status": "READY",
			"workflowName": "cttsov2",
			"workflowVersion": "2.6.0",
			"workflowRunName": "umccr--automated--cttsov2--2-6-0--20250424109aedfe",
			"linkedLibraries": [
				{
					"libraryId": "L2201125",
					"orcabusId": "lib.01JBMV1W6J7AAMVFRBS90KX8Q3"
				}
			],
			"payload": {
				"version": "2024.07.01",
				"data": {
					"inputs": {
						"sampleId": "PRJ221875_L2201125",
						"samplesheet": {...},
						"instrumentRunId": "220816_A00130_0223_AH7KG5DMXY",
						"fastqListRows": [...]
					},
					"engineParameters": {
						"cacheUri": "s3://pipeline-montauk-977251586657-ap-southeast-2/byob-icav2/montauk-prod/cache/cttsov2/20250424109aedfe/",
						"outputUri": "s3://pipeline-montauk-977251586657-ap-southeast-2/byob-icav2/montauk-prod/analysis/cttsov2/20250424109aedfe/",
						"logsUri": "s3://pipeline-montauk-977251586657-ap-southeast-2/byob-icav2/montauk-prod/logs/cttsov2/20250424109aedfe/",
						"pipelineId": "c2dfdbaa-2074-44c7-8078-d33e13607061",
						"projectId": "523d7282-9d31-4512-8fca-2aebcbb89d01"
					},
					"tags": {
						"libraryId": "L2201125",
						"fastqListRowIds": [
							"GAATAATC.GCCTCTAT.1.220816_A00130_0223_AH7KG5DMXY.L2201125",
							"GAATAATC.GCCTCTAT.2.220816_A00130_0223_AH7KG5DMXY.L2201125"
						]
					}
				}
			}
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

    portal_run_id = str(detail.get('portalRunId', ""))
    status = str(detail.get('status', ""))
    state_timestamp = str(detail.get('timestamp', ""))
    workflow_name = str(detail.get('workflowName', ""))
    workflow_version = str(detail.get('workflowVersion', ""))
    workflow_run_name = str(detail.get('workflowRunName', ""))
    libraries = detail.get('linkedLibraries', {})


    data = {
        "event_id": event_id,
        "event_time": event_time,
        "portal_run_id": portal_run_id,
        "status": status,
        "state_timestamp": state_timestamp,
        "workflow_name": workflow_name,
        "workflow_version": workflow_version,
        "workflow_run_name": workflow_run_name,
        "libraries": json.dumps(libraries),
        "load_datetime": datetime.datetime.now().isoformat(),
        "record_source": RECORD_SOURCE
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
