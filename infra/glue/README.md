# Glue

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
terraform workspace list
  default
* prod
```

```
export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan
terraform apply
```

## Run

```
export AWS_PROFILE=umccr-prod-admin
```

```
aws glue list-jobs
{
    "JobNames": [
        "orcahouse-spreadsheet-library-tracking-metadata-job"
    ]
}
```

```
aws glue start-job-run --job-name orcahouse-spreadsheet-library-tracking-metadata-job
{
    "JobRunId": "jr_ec42af440ad35b948b2af17b88459a31a2248275f464c6a353638349f9d178d1"
}
```

```
aws glue get-job-run --job-name orcahouse-spreadsheet-library-tracking-metadata-job --run-id jr_ec42af440ad35b948b2af17b88459a31a2248275f464c6a353638349f9d178d1
{
    "JobRun": {
        "Id": "jr_ec42af440ad35b948b2af17b88459a31a2248275f464c6a353638349f9d178d1",
        "Attempt": 0,
        "JobName": "orcahouse-spreadsheet-library-tracking-metadata-job",
        "JobMode": "SCRIPT",
        "JobRunQueuingEnabled": false,
        "StartedOn": "2025-01-11T17:12:49.739000+11:00",
        "LastModifiedOn": "2025-01-11T17:14:48.111000+11:00",
        "CompletedOn": "2025-01-11T17:14:48.111000+11:00",
        "JobRunState": "SUCCEEDED",
        "PredecessorRuns": [],
        "AllocatedCapacity": 1,
        "ExecutionTime": 106,
        "Timeout": 15,
        "MaxCapacity": 1.0,
        "WorkerType": "Standard",
        "NumberOfWorkers": 1,
        "LogGroupName": "/aws-glue/jobs",
        "GlueVersion": "5.0"
    }
}
```

Or, use UI AWS Glue Console.
