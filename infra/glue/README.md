# Glue

<!-- TOC -->
* [Glue](#glue)
  * [Local Development](#local-development)
  * [Deploy](#deploy)
  * [Run](#run)
  * [Query](#query)
<!-- TOC -->

We use AWS Glue to drive all structure/semi-structure data from sources into warehouse staging layer.

## Local Development

```
uv venv --python 3.10
source .venv/bin/activate
uv pip install -r requirements-dev.txt
```

```
aws sso login
assume umccr-dev-admin
```

Consider this public JSON line dataset.

```
aws s3 ls s3://awsglue-datasets/examples/us-legislators/all/persons.json
```

```
make up
make spark
make glue
```

Then inside Glue container, you can run the job or test like so.
```
ls -l jupyter_workspace/
cd jupyter_workspace/skel/
spark-submit sample.py
pytest
```

This gives local spark dev & debug routine before deploying the job script to remote.


## Deploy

```
cd deploy
```

```
export AWS_PROFILE=umccr-dev-admin
```

```
terraform workspace list
  default
* dev
  prod
```

```
export AWS_PROFILE=umccr-dev-admin && terraform workspace select dev && terraform plan
terraform apply
```

## Run

```
export AWS_PROFILE=umccr-dev-admin
```

```
aws glue list-jobs
{
    "JobNames": [
        "orcahouse-spreadsheet-google-lims-job",
        "orcahouse-spreadsheet-library-tracking-metadata-job"
    ]
}
```

```
aws glue start-job-run --job-name orcahouse-spreadsheet-library-tracking-metadata-job
{
    "JobRunId": "jr_c2038f07ebe8dde73da0c9d2fdef2b14a9ff64fe90a29ac244e76464d52bebe1"
}
```

```
aws glue get-job-run --job-name orcahouse-spreadsheet-library-tracking-metadata-job --run-id jr_c2038f07ebe8dde73da0c9d2fdef2b14a9ff64fe90a29ac244e76464d52bebe1
{
    "JobRun": {
        "Id": "jr_c2038f07ebe8dde73da0c9d2fdef2b14a9ff64fe90a29ac244e76464d52bebe1",
        "Attempt": 0,
        "JobName": "orcahouse-spreadsheet-library-tracking-metadata-job",
        "JobMode": "SCRIPT",
        "JobRunQueuingEnabled": false,
        "StartedOn": "2025-09-03T14:15:09.917000+10:00",
        "LastModifiedOn": "2025-09-03T14:15:13.843000+10:00",
        "JobRunState": "RUNNING",
        "PredecessorRuns": [],
        "AllocatedCapacity": 2,
        "ExecutionTime": 0,
        "Timeout": 15,
        "MaxCapacity": 2.0,
        "WorkerType": "G.1X",
        "NumberOfWorkers": 2,
        "LogGroupName": "/aws-glue/jobs",
        "GlueVersion": "5.0"
    }
}
```

Or, use UI AWS Glue Console.


## Query

You can query via [OrcaHouse Athena](https://github.com/umccr/orcahouse-doc/tree/main/athena) (only in DEV) or via [db tunnel setup](../ec2/README.md) for TSA schema tables.  

```sql
select * from tsa.spreadsheet_library_tracking_metadata;
select * from tsa.spreadsheet_google_lims;
```
