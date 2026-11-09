# Glue Clawer for orcabus-db datalake

This stack provisions a Glue Clawer for the orcabus-db datalake created by the [DMS CDC stack](../../dms/orcabus-db).

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

## When the crawlers run

The crawlers have no schedule. The OrcaVault sources stage starts them before
each run, in both dev and prod, see
[infra/orcavault-run](../../orcavault-run/README.md#sources). To crawl now, start
a crawler from the console, or the sources stage with `{}`.

Each crawl only crawls new folders, which adds the day's new partitions quickly.
