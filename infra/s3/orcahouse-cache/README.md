# OrcaHouse Cache Bucket

Thy shall be referred to as `cache` bucket.

This stack creates orcahouse cache buckets for some intermediate files for a short-term storage purpose. 

e.g. ETL pipeline temp files, Athena query results, etc.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```
