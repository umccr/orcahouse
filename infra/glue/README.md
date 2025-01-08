# Glue

We use AWS Glue to drive all structure/semi-structure into *Staging* layer of our warehouse. This technique is called data preloading.

## Local Development

```
uv venv --python 3.10
source .venv/bin/activate
uv pip install -r requirements-dev.txt
```

```
aws sso login
assume -r umccr-dev-admin
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
