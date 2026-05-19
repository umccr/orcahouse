import glob
import json
import os
import sys

import polars as pl
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from libumccr.aws import libssm, libsm, libs3
from pyspark.sql import SparkSession

BASE_NAME = "ica_usage_report"
SCHEMA_NAME = "tsa"
DB_NAME = "orcavault"

OUT_NAME_DOT = f"{DB_NAME}.{SCHEMA_NAME}.{BASE_NAME}"
OUT_NAME = f"{DB_NAME}_{SCHEMA_NAME}_{BASE_NAME}"
OUT_PATH = f"/tmp/{OUT_NAME}"

S3_SOURCE_PREFIX = "ica-usage-reports/"
S3_MID_PATH = "glue/csv_ica_usage_report"

REGION_NAME = "ap-southeast-2"


def extract(s3_bucket_name: str):
    s3_client = libs3.s3_client()
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=s3_bucket_name, Prefix=S3_SOURCE_PREFIX)

    keys = [
        obj['Key']
        for page in pages
        for obj in page.get('Contents', [])
        if obj['Key'].endswith('.csv')
    ]

    assert len(keys) > 0, f'No CSV files found under s3://{s3_bucket_name}/{S3_SOURCE_PREFIX}'

    for key in keys:
        filename = os.path.basename(key)
        local_path = f"{OUT_PATH}__{filename}"
        s3_client.download_file(s3_bucket_name, key, local_path)
        print(f"Downloaded: {key}")


def transform():
    files = sorted(glob.glob(f"{OUT_PATH}__*.csv"))
    assert len(files) > 0, 'No downloaded CSV files to transform'

    frames = []
    for f in files:
        df = pl.read_csv(f, infer_schema_length=False, infer_schema=False)
        df.columns = [c.lower() for c in df.columns]
        df = df.with_columns(pl.col(pl.String).str.strip_chars())
        df = df.filter(~pl.all_horizontal(pl.all().is_null()))
        frames.append(df)
        print(f, df.columns)

    df = pl.concat(frames)

    df.write_csv(f"{OUT_PATH}.csv")

    # generate sql schema script
    sql = ""
    i = 1
    for col in df.columns:
        if col in ['record_source', 'load_datetime']:
            continue
        if i == len(df.columns):
            sql += f'{col}\tvarchar'
        else:
            sql += f'{col}\tvarchar,\n'
        i += 1

    sql_schema = f"""CREATE TABLE IF NOT EXISTS {OUT_NAME_DOT}
    (
    {sql}
    );"""

    with open(f"{OUT_PATH}.sql", 'w', newline='') as f:
        f.write(sql_schema)

    print(sql_schema)


def load(spark: SparkSession, s3_bucket_name: str):
    csv_file, sql_file = f"{OUT_PATH}.csv", f"{OUT_PATH}.sql"

    csv_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(csv_file)}"
    sql_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(sql_file)}"

    s3_client = libs3.s3_client()
    s3_client.upload_file(csv_file, s3_bucket_name, csv_s3_object_name)
    s3_client.upload_file(sql_file, s3_bucket_name, sql_s3_object_name)

    def load_db():
        tsa_username = libssm.get_ssm_param("/orcahouse/orcavault/tsa_username")
        secret_value = libsm.get_secret(f"orcahouse/orcavault/{tsa_username}")
        secret = json.loads(secret_value)

        db_user = secret['username']
        db_password = secret['password']
        db_host = secret['host']
        db_port = secret['port']
        db_name = secret['dbname']
        assert db_name == DB_NAME, 'db_name mismatch'

        jdbc_url = f"jdbc:postgresql://{db_host}:{db_port}/{db_name}"
        table_name = f"{SCHEMA_NAME}.{BASE_NAME}"
        csv_file_path = csv_s3_object_name

        # truncate the table

        df = spark.read \
            .jdbc(url=jdbc_url, table=table_name, properties={"user": db_user, "password": db_password})

        print(df.count())

        df.write \
            .option("truncate", True) \
            .jdbc(url=jdbc_url, table=table_name, properties={"user": db_user, "password": db_password},
                  mode="overwrite")

        print("Truncated")

        # import csv from s3

        import_sql = f"""
            SELECT aws_s3.table_import_from_s3(
                '{table_name}',
                '',
                '(FORMAT csv, HEADER true, DELIMITER ",")',
                '{s3_bucket_name}',
                '{csv_file_path}',
                '{REGION_NAME}'
            )
        """
        df_s3 = spark.read.format("jdbc") \
            .option("url", jdbc_url) \
            .option("user", db_user) \
            .option("password", db_password) \
            .option("query", import_sql) \
            .load()

        print(df_s3.count() == 1)

        print(df.count())
        print(df.printSchema())

    load_db()  # comment if local dev


def clean_up():
    pass  # for now


class GlueIcaUsageReport(Job):
    def __init__(self, glue_context):
        super().__init__(glue_context)

        params = ['bucket']

        if '--JOB_NAME' in sys.argv:
            params.append('JOB_NAME')
        args = getResolvedOptions(sys.argv, params)

        self.job = Job(glue_context)
        self.spark: SparkSession = glue_context.spark_session

        self.s3_bucket_name = args['bucket']

        if 'JOB_NAME' in args:
            job_name = args['JOB_NAME']
        else:
            job_name = "GlueIcaUsageReport"
        self.job.init(job_name, args)

    def run(self):
        extract(self.s3_bucket_name)
        transform()
        load(self.spark, self.s3_bucket_name)
        clean_up()
        self.job.commit()


if __name__ == '__main__':
    gc = GlueContext(SparkSession.builder.getOrCreate())
    GlueIcaUsageReport(gc).run()
