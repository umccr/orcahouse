import os
import json
import boto3
import psycopg2

DEBUG = False

# function to retrieve DB credetials
def get_secret(secret_name, client):
    """
    Retrieve secret from AWS Secrets Manager
    """
    print("Retrieving DB credentials from Secrets Manager...")

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


def push_to_db(conn, statement, data):
    print("Pushing data to database...")
    with conn:
        with conn.cursor() as cur:
            values = str(tuple(data.values()))[1:-1]  # strip off tuple brackets
            sql = cur.mogrify(
                statement,
                (AsIs(",".join(data.keys())), AsIs(values), data["event_id"]),
            )
            print(f"SQL to execute: {sql}")
            if DEBUG:
                print("Debugging, not executing SQL.")
            else:
                print("Executing SQL...")
                cur.execute(sql)

    print("Data pushed to database!")


def isDebug():
    return DEBUG

