import csv
import json
import os
import sys

import gspread
import polars as pl
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from libumccr.aws import libssm, libsm, libs3
from pyspark.sql import SparkSession

# The datasource spreadsheet configuration
GDRIVE_SERVICE_ACCOUNT = "/umccr/google/drive/lims_service_account_json"
LIMS_SHEET_ID = "/umccr/google/drive/lims_sheet_id"
SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
SHEET_NAME = "Sheet1"

# NOTE: this is intended db table naming convention
# i.e. <datasource>_<suffix_meaningful_naming_convention>
# e.g. <spreadsheet>_<some_research_data_collection>
BASE_NAME = "spreadsheet_google_lims"
SCHEMA_NAME = "tsa"
DB_NAME = "orcavault"

# Prepare out path with naming convention
OUT_NAME_DOT = f"{DB_NAME}.{SCHEMA_NAME}.{BASE_NAME}"
OUT_NAME = f"{DB_NAME}_{SCHEMA_NAME}_{BASE_NAME}"
OUT_PATH = f"/tmp/{OUT_NAME}"

S3_MID_PATH = f"glue/{BASE_NAME}"

REGION_NAME = "ap-southeast-2"


def extract():
    spreadsheet_id = libssm.get_secret(LIMS_SHEET_ID)
    account_info = libssm.get_secret(GDRIVE_SERVICE_ACCOUNT)

    gs = gspread.service_account_from_dict(json.loads(account_info))
    sh = gs.open_by_key(spreadsheet_id)

    worksheet = sh.worksheet(SHEET_NAME)
    filename = f"{OUT_PATH}__{SHEET_NAME}.csv"
    with open(filename, 'w') as f:
        writer = csv.writer(f)
        writer.writerows(worksheet.get_all_values())


def transform():
    # treat all columns as string value, do not automatically infer the dataframe dtype i.e. infer_schema_length=0
    # https://github.com/pola-rs/polars/pull/16840
    # https://stackoverflow.com/questions/77318631/how-to-read-all-columns-as-strings-in-polars
    df = pl.read_csv(f"{OUT_PATH}__{SHEET_NAME}.csv", infer_schema_length=False, infer_schema=False)

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
    # df = df.select(sorted(df.columns))

    # drop all unnamed (blank) columns
    for col in df.columns:
        if col.startswith('__UNNAMED__'):
            df = df.drop(col)
        if col.startswith('_duplicated'):
            df = df.drop(col)
        if col == '':
            df = df.drop(col)

    # add sheet name as a column
    df = df.with_columns(pl.lit(SHEET_NAME).alias('sheet_name'))

    print(SHEET_NAME, df.columns)

    # final column rename
    df = df.rename({
        'IlluminaID': 'illumina_id',
        'Run': 'run',
        'Timestamp': 'timestamp',
        'SubjectID': 'subject_id',
        'SampleID': 'sample_id',
        'LibraryID': 'library_id',
        'ExternalSubjectID': 'external_subject_id',
        'ExternalSampleID': 'external_sample_id',
        'ExternalLibraryID': 'external_library_id',
        'SampleName': 'sample_name',
        'ProjectOwner': 'project_owner',
        'ProjectName': 'project_name',
        'ProjectCustodian': 'project_custodian',
        'Type': 'type',
        'Assay': 'assay',
        'OverrideCycles': 'override_cycles',
        'Phenotype': 'phenotype',
        'Source': 'source',
        'Quality': 'quality',
        'Topup': 'topup',
        'SecondaryAnalysis': 'secondary_analysis',
        'Workflow': 'workflow',
        'Tags': 'tags',
        'FASTQ': 'fastq',
        'NumberFASTQS': 'number_fastqs',
        'Results': 'results',
        'Trello': 'trello',
        'Notes': 'notes',
        'Todo': 'todo'
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

    sql_schema = f"""CREATE TABLE IF NOT EXISTS {OUT_NAME_DOT}
    (
    {sql}
    );"""

    with open(f"{OUT_PATH}.sql", 'w', newline='') as f:
        f.write(sql_schema)

    print(sql_schema)


def load(spark: SparkSession, s3_bucket_name: str):
    # load staging data from the temporary location by naming convention
    csv_file, sql_file = f"{OUT_PATH}.csv", f"{OUT_PATH}.sql"

    # construct s3 object name

    csv_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(csv_file)}"
    sql_s3_object_name = f"{S3_MID_PATH}/{os.path.basename(sql_file)}"

    # load data into S3

    s3_client = libs3.s3_client()

    s3_client.upload_file(csv_file, s3_bucket_name, csv_s3_object_name)
    s3_client.upload_file(sql_file, s3_bucket_name, sql_s3_object_name)

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

        # after data loading complete

        print(df.count())
        print(df.printSchema())

    load_db()  # comment if local dev


def clean_up():
    # os.remove(LOCAL_TEMP_FILE)
    pass  # for now


class GlueGoogleLIMS(Job):
    def __init__(self, glue_context):
        super().__init__(glue_context)

        # Pass-in parameters
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
            job_name = "GlueGoogleLIMS"
        self.job.init(job_name, args)

    def run(self):

        extract()

        transform()

        load(self.spark, self.s3_bucket_name)

        clean_up()

        self.job.commit()


if __name__ == '__main__':
    gc = GlueContext(SparkSession.builder.getOrCreate())
    GlueGoogleLIMS(gc).run()
