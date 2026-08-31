# OrcaVault Warehouse Bucket

Thy shall be referred to as `orcavault warehouse` bucket.

This stack provisions the S3 bucket for OrcaVault data mart purpose. 

The buckets are used for Redshift warehouse UNLOAD target.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```
