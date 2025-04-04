import os
import json
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor


FQR_DETAIL_TYPE = "FastqListRowUpdated"
FQR_EVENT_SOURCE = "orcabus.fastqmanager"
# Get the secret name from environment variables
DB_SECRET_NAME = os.environ['DB_SECRET_NAME']

SQL_INSERT = "INSERT INTO FastqListRows (%s) VALUES (%s);"

def get_secret(secret_name):
    """Retrieve secret from AWS Secrets Manager"""
    print(f"Retrieving DB credentials from Secrets Manager ({secret_name})...")
    session = boto3.session.Session()
    client = boto3.client('secretsmanager')
    
    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        raise e
    else:
        if 'SecretString' in get_secret_value_response:
            secret = json.loads(get_secret_value_response['SecretString'])
            return secret
        else:
            print("Secret not found!")


def get_db_connection(credentials):
    print("Establishing connection to database...")
    username = credentials.get('username')
    password = credentials.get('password')
    host = credentials.get('host')
    port = credentials.get('port')
    dbname = credentials.get('dbname')
    print(f"Connecting to {host}:{port} as {username}...")        

    conn = psycopg2.connect(
        host=host,
        database=dbname,
        user=username,
        password=password,
        port=port
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
        # Get database connection
        
        # test_case()
        fdata = parse_event(event)
        push_to_db(fdata)


        # # Clean up
        # cur.close()
        # conn.close()
        
        print("Returning results.")
        return {
            'statusCode': 200,
            'body': json.dumps(results_list)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def parse_event(event):
    # Parse the event and extract the FQR code
    # This is a placeholder function and should be implemented based on the actual event structure
    """
    Example FastqListRowUpdated event:
    {
        "version": "0",
        "id": "c963f8ef-f852-9bdb-22df-a08e01274852",
        "detail-type": "FastqListRowUpdated",
        "source": "orcabus.fastqmanager",
        "account": "472057503814",
        "time": "2025-04-03T00:24:30Z",
        "region": "ap-southeast-2",
        "resources": [],
        "detail": {
            "id": "fqr.01JQTJ0KT4WPVWET3GBS69H1JC",
            "fastqSetId": "fqs.01JQTJ0KXQN0HJNWK2CE7TGT8D",
            "index": "ATGTTCCT+GGCGCTGA",
            "lane": 4,
            "instrumentRunId": "250228_A00130_0359_AHCCNCDSXF",
            "library": {
                "orcabusId": "lib.01JN13SABNQGP3140F9PD6K851",
                "libraryId": "L2500151"
            },
            "platform": "Illumina",
            "center": "UMCCR",
            "date": "2025-02-28T00:00:00",
            "readSet": {
                "r1": {
                    "gzipCompressionSizeInBytes": 17725167693,
                    "rawMd5sum": "471e6caeed74802a8f38b4c1307ed85d",
                    "ingestId": "0195f74f-bbff-7a31-9fcd-695f1ecb5ca2",
                    "s3Uri": "s3://pipeline-prod-cache-503977275616-ap-southeast-2/byob-icav2/production/ora-compression/250228_A00130_0359_AHCCNCDSXF/202504027941308e/Samples/Lane_2/L2500156/L2500156_S12_L002_R1_001.fastq.ora",
                    "storageClass": "Standard"
                },
                "r2": {
                    "gzipCompressionSizeInBytes": 18783837974,
                    "rawMd5sum": "30cb6f04cf33349c37155fed430994e6",
                    "ingestId": "0195f74f-d023-7b03-bb48-1e44f14e51ce",
                    "s3Uri": "s3://pipeline-prod-cache-503977275616-ap-southeast-2/byob-icav2/production/ora-compression/250228_A00130_0359_AHCCNCDSXF/202504027941308e/Samples/Lane_2/L2500156/L2500156_S12_L002_R2_001.fastq.ora",
                    "storageClass": "Standard"
                },
                "compressionFormat": "ORA"
            },
            "qc": null,
            "readCount": 70664,
            "baseCountEst": 21340528,
            "isValid": true,
            "ntsm": null
        }
    }
    """
    detail_type = event.get('detail-type')
    event_source = event.get('source')

    if detail_type != FQR_DETAIL_TYPE:
        raise ValueError(f"Invalid event type. Expected '{FQR_DETAIL_TYPE}' but got '{detail_type}'")
    if event_source != FQR_EVENT_SOURCE:
        raise ValueError(f"Invalid event source. Expected '{FQR_EVENT_SOURCE}' but got '{event_source}'")

    event_time = event.get('time')
    detail = event.get('detail')

    fqr_id = detail.get('id')
    instrument_run_id = detail.get('instrumentRunId')
    library = detail.get('library').get('libraryId')
    lane = detail.get('lane')
    is_valid = detail.get('isValid')
    fqr_date = detail.get('date')  # TODO: check with Alexis what this date is

    readset = detail.get('readset')
    if readset:
        readset_r1 = readset.get('r1').get('ingestId')
        readset_r2 = readset.get('r2').get('ingestId')

    fqr_data = {
        "event_time": event_time,
        "fqr_id": fqr_id,
        "instrument_run_id": instrument_run_id,
        "library": library,
        "lane": lane,
        "is_valid": is_valid,
        "fqr_date": fqr_date,
        "readset_r1": readset_r1,
        "readset_r2": readset_r2
    }
    print(f"Extracted data: {fqr_data}")

    return fqr_data


def push_to_db(data):
    print("Pushing data to database...")
    with DB_CONNECTION:
        with DB_CONNECTION.cursor() as cur:
            # cur.execute(SQL_INSERT, (data.keys(), data.values()))
            sql = cur.mogrify(SQL_INSERT, (data.keys(), data.values()))
            print(f"SQL: {sql}")

    print("Data pushed to database!")


def test_case():
    # Execute example query
    print("Executing query...")
    with DB_CONNECTION:
        with DB_CONNECTION.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM django_migrations LIMIT 5")
            results = cur.fetchall()
    
    # Convert results to JSON-serializable format
    print("Query executed successfully!")
    results_list = [dict(row) for row in results]
    print(f"Results: {results_list}")
