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

## Picking up a schema change

Crawling new folders only forces the crawlers to log a schema change rather than
apply it, see
[incremental crawls](https://docs.aws.amazon.com/glue/latest/dg/incremental-crawls.html).
So when an OrcaBus table gains a column, its catalog table doesn't, until a full
crawl. `full_crawl` switches the crawlers to crawl everything and add new
columns, without changing or removing existing ones:

```
terraform apply -var full_crawl=true
aws glue start-crawler --name orcabus-db-crawler-<database>
aws glue get-crawler --name orcabus-db-crawler-<database> --query 'Crawler.[State,LastCrawl.Status]'

# Once it has finished, switch back.
terraform apply
```

A full crawl takes longer than a nightly one, so do it outside the nightly
chain, or the sources stage may report it as `TIMEOUT`.
