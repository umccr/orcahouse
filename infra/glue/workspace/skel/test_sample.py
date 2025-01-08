import sys

import pytest
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession

import sample


@pytest.fixture(scope="module", autouse=True)
def glue_context():
    sys.argv.append('--JOB_NAME')
    sys.argv.append('test_count')

    args = getResolvedOptions(sys.argv, ['JOB_NAME'])
    context = GlueContext(SparkSession.builder.getOrCreate())
    job = Job(context)
    job.init(args['JOB_NAME'], args)

    yield context

    job.commit()


def test_count(glue_context):
    dyf = sample.read_json(glue_context, "s3://awsglue-datasets/examples/us-legislators/all/persons.json")
    assert dyf.toDF().count() == 1961
