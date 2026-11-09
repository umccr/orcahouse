# Glue Clawer for orcavault-db datalake

This stack provisions a Glue Clawer for the orcavault-db datalake created by the Redshift UNLOAD process.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

## When the crawler runs

The crawler runs on its own daily schedule. The OrcaVault chain starts only the
upstream CDC crawlers, see
[orcabus-db](../orcabus-db/README.md#when-the-crawlers-run), so this mart crawler
isn't part of the chain yet, see
[issue #58](https://github.com/umccr/orcahouse-project/issues/58). To crawl now,
start the crawler from the console.

Prod isn't applied yet. Once it is, add `orcavault-db-prod-mart-crawler` to the
prod notification `crawler_names`.
