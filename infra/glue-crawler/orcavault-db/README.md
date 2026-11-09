# Glue Clawer for orcavault-db datalake

This stack provisions a Glue Clawer for the orcavault-db datalake created by the Redshift UNLOAD process.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

## When the crawler runs

The crawler has no schedule. The OrcaVault publish stage starts it after each
run that applied its models, see
[infra/orcavault-run](../../orcavault-run/README.md#publish). To crawl now, start
the crawler from the console, or the publish stage with `{}`.

Prod isn't applied yet. Once it is, add `orcavault-db-prod-mart-crawler` to the
prod publish stage's `mart_crawler_names`, and to the prod notification
`crawler_names`.
