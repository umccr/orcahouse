import os
import json
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor

# Get the secret name from environment variables
DB_SECRET_NAME = os.environ['DB_SECRET_NAME']

def get_secret(secret_name):
    """Retrieve secret from AWS Secrets Manager"""
    print("Retrieving DB credentials from Secrets Manager...")
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
    print("Connecting to the database...")        

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
        cur = DB_CONNECTION.cursor(cursor_factory=RealDictCursor)
        
        # Execute your query
        print("Executing query...")
        cur.execute("SELECT * FROM django_migrations LIMIT 5")
        results = cur.fetchall()
        
        # Convert results to JSON-serializable format
        print("Query executed successfully!")
        results_list = [dict(row) for row in results]
        print(f"Results: {results_list}")
        
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
