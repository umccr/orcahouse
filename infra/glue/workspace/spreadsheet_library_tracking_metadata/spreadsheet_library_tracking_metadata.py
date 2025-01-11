import json
import os
import sys

import polars as pl
import requests
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials
from libumccr.aws import libssm, libsm, libs3
from pyspark.sql import SparkSession

# The datasource spreadsheet configuration
GDRIVE_SERVICE_ACCOUNT = "/umccr/google/drive/lims_service_account_json"
TRACKING_SHEET_ID = "/umccr/google/drive/tracking_sheet_id"
SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
SHEETS = ['2017', '2018', '2019', '2020', '2021', '2022', '2023', '2024', '2025']

# NOTE: this is intended db table naming convention
# i.e. <datasource>_<suffix_meaningful_naming_convention>
# e.g. <spreadsheet>_<some_research_data_collection>
BASE_NAME = "spreadsheet_library_tracking_metadata"
SCHEMA_NAME = "tsa"
DB_NAME = "orcavault"

# Prepare out path with naming convention
OUT_NAME = f"{DB_NAME}_{SCHEMA_NAME}_{BASE_NAME}"
OUT_PATH = f"/tmp/{OUT_NAME}"

S3_BUCKET = "orcahouse-staging-data-472057503814"
S3_MID_PATH = f"glue/{BASE_NAME}"

REGION_NAME = "ap-southeast-2"


def extract():
    spreadsheet_id = libssm.get_secret(TRACKING_SHEET_ID)
    account_info = libssm.get_secret(GDRIVE_SERVICE_ACCOUNT)
    credentials: Credentials = Credentials.from_service_account_info(json.loads(account_info), scopes=SCOPES)
    credentials.refresh(Request())

    export_url = f"https://www.googleapis.com/drive/v3/files/{spreadsheet_id}/export?mimeType=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    headers = {
        'Authorization': f'Bearer {credentials.token}',
    }

    response = requests.get(export_url, headers=headers)
    if response.status_code == 200:
        with open(f"{OUT_PATH}.xlsx", 'wb') as file:
            file.write(response.content)
    else:
        raise Exception(f"Failed to download spreadsheet: {response.status_code} - {response.text}")


def transform():
    row_count = 0
    frames = []

    for sheet in SHEETS:

        # treat all columns as string value, do not automatically infer the dataframe dtype i.e. infer_schema_length=0
        # https://github.com/pola-rs/polars/pull/16840
        # https://stackoverflow.com/questions/77318631/how-to-read-all-columns-as-strings-in-polars
        df = pl.read_excel(f"{OUT_PATH}.xlsx", sheet_name=sheet, infer_schema_length=0)

        # handle sheet specific cases
        match sheet:
            case '2017':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2018':
                df = df.rename({
                    'Baymax run#': 'Run#',
                    'Index ': 'TruSeq Index, unless stated',
                    'Study': 'zStudy',
                })
                df = df.with_columns(pl.lit('').alias('SampleName'))
                df = df.with_columns(pl.lit('').alias('Sample_ID (SampleSheet)'))
                df = df.with_columns(pl.lit('').alias('qPCR ID'))
            case '2019':
                df = df.rename({
                    'IDT Index , unless stated': 'TruSeq Index, unless stated',
                })
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2020':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2021':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2022':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2023':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2024':
                df = df.with_columns(pl.lit('').alias('zStudy'))
            case '2025':
                df = df.with_columns(pl.lit('').alias('zStudy'))

        # globally rename
        df = df.rename({
            'Coverage (X)': 'Coverage',
            'TruSeq Index, unless stated': 'TruSeqIndex',
            'Run#': 'Run',
            'qPCR ID': 'QPCRID',
            'Sample_ID (SampleSheet)': 'SampleSheetID',
        })

        # replace all cells that contain well-known placeholder characters, typically derived formula columns
        df = df.with_columns(pl.col(pl.String).str.replace("^_$", ""))
        df = df.with_columns(pl.col(pl.String).str.replace("^__$$", ""))
        df = df.with_columns(pl.col(pl.String).str.replace("^-$", ""))
        df = df.with_columns(
            pl.when(pl.col(pl.String).str.len_chars() == 0)
            .then(None)
            .otherwise(pl.col(pl.String))
            .name.keep()
        )

        # strip whitespaces, carriage return
        df = df.with_columns(pl.col(pl.String).str.strip_chars())

        # drop row iff all values are null
        # https://docs.pola.rs/api/python/stable/reference/dataframe/api/polars.DataFrame.drop_nulls.html
        df = df.filter(~pl.all_horizontal(pl.all().is_null()))

        # sort the columns
        df = df.select(sorted(df.columns))

        # drop all unnamed (blank) columns
        for col in df.columns:
            if col.startswith('__UNNAMED__'):
                df = df.drop(col)

        # add sheet name as a column
        df = df.with_columns(pl.lit(sheet).alias('sheet_name'))

        row_count += df.shape[0]

        frames.append(df)

    # ---

    # combine all sheets
    df = pl.concat(frames)
    assert df.shape[0] == row_count, 'row count mismatch'

    # final column rename
    df = df.rename({
        'Assay': 'assay',
        'Comments': 'comments',
        'Coverage': 'coverage',
        'ExperimentID': 'experiment_id',
        'ExternalSampleID': 'external_sample_id',
        'ExternalSubjectID': 'external_subject_id',
        'LibraryID': 'library_id',
        'OverrideCycles': 'override_cycles',
        'Phenotype': 'phenotype',
        'ProjectName': 'project_name',
        'ProjectOwner': 'project_owner',
        'QPCRID': 'qpcr_id',
        'Quality': 'quality',
        'Run': 'run',
        'SampleID': 'sample_id',
        'SampleName': 'sample_name',
        'SampleSheetID': 'samplesheet_sample_id',
        'Source': 'source',
        'SubjectID': 'subject_id',
        'TruSeqIndex': 'truseq_index',
        'Type': 'type',
        'Workflow': 'workflow',
        'rRNA': 'r_rna',
        'zStudy': 'study',
    })

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

    sql_schema = f"""CREATE TABLE IF NOT EXISTS {OUT_NAME}
    (
    {sql}
    );"""

    with open(f"{OUT_PATH}.sql", 'w', newline='') as f:
        f.write(sql_schema)

    print(sql_schema)


def load(spark: SparkSession):
    # load staging data from the temporary location by naming convention
    csv_file, sql_file, xls_file = f"{OUT_PATH}.csv", f"{OUT_PATH}.sql", f"{OUT_PATH}.xlsx"

    # construct s3 object name

    csv_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(csv_file)}"
    sql_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(sql_file)}"
    xls_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(xls_file)}"

    # load data into S3

    s3_client = libs3.s3_client()

    s3_client.upload_file(csv_file, S3_BUCKET, csv_s3_object_name)
    s3_client.upload_file(sql_file, S3_BUCKET, sql_s3_object_name)
    s3_client.upload_file(xls_file, S3_BUCKET, xls_s3_object_name)

    # load data into database

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
        bucket_name = S3_BUCKET
        csv_file_path = csv_s3_object_name

        # truncate the table

        df = spark.read \
            .jdbc(url=jdbc_url, table=table_name, properties={"user": db_user, "password": db_password})

        print(df.count())

        df.write \
            .option("truncate", True) \
            .jdbc(url=jdbc_url, table=table_name, properties={"user": db_user, "password": db_password}, mode="overwrite")

        print("Truncated")

        # import csv from s3

        import_sql = f"""
            SELECT aws_s3.table_import_from_s3(
                '{table_name}',
                '',
                '(FORMAT csv, HEADER true, DELIMITER ",")',
                '{bucket_name}',
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

        # after data loading complete

        print(df.count())
        print(df.printSchema())

    load_db()  # comment if local dev


def clean_up():
    # os.remove(LOCAL_TEMP_FILE)
    pass  # for now


class GlueLibraryTrackingMetadata(Job):
    def __init__(self, glue_context):
        super().__init__(glue_context)
        params = []
        if '--JOB_NAME' in sys.argv:
            params.append('JOB_NAME')
        args = getResolvedOptions(sys.argv, params)

        self.job = Job(glue_context)
        self.spark: SparkSession = glue_context.spark_session

        if 'JOB_NAME' in args:
            job_name = args['JOB_NAME']
        else:
            job_name = "GlueLibraryTrackingMetadata"
        self.job.init(job_name, args)

    def run(self):

        extract()

        transform()

        load(self.spark)

        clean_up()

        self.job.commit()


if __name__ == '__main__':
    gc = GlueContext(SparkSession.builder.getOrCreate())
    GlueLibraryTrackingMetadata(gc).run()
