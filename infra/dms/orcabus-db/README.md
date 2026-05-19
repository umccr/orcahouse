# DMS CDC Service for orcabus-db

This stack provisions CDC (Change Data Capture) infrastructure by leveraging AWS managed solution – AWS DMS service.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

## Architecture

See [epic ticket](https://github.com/umccr/orcahouse/issues/105) for the solution architecture references.

tl;dr

```
Aurora PostgreSQL → DMS CDC → S3 datalake (parquet)
```
