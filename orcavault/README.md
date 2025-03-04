# OrcaVault

OrcaVault is a dbt project. It contains data warehouse models.

## Local Development

```
make up
make ps
make all
make psql
orcavault=> \l
orcavault=> \dn
orcavault=> \dn ods
orcavault=> set search_path to ods;
orcavault=> \dt
orcavault=> \d data_portal_labmetadata
orcavault=> select count(1) from data_portal_labmetadata;
orcavault=> set search_path to tsa;
orcavault=> \dt
orcavault=> \d spreadsheet_library_tracking_metadata
orcavault=> select count(1) from spreadsheet_library_tracking_metadata;
orcavault=> \q
```

```
dbt debug
dbt clean
dbt deps
dbt build
dbt run
```

```
make psql
orcavault=> set search_path to raw;
orcavault=> \dt
orcavault=> \d hub_library
orcavault=> select count(1) from hub_library;
orcavault=> \q
```

### Make Load

To this point, it is good enough to work with structural changes and transformation from previous section i.e. data model development purpose. If you would like to try ELT process with snapshot test data, you can sync from dev bucket. Steps are as follows.

```
export AWS_PROFILE=umccr-dev-admin
make sync
make load next
```

Observe to tables from schema `ods` `tsa` and make some query.

```
dbt test
dbt build
dbt run
```

Observe to tables from schema `psa` `raw` and make some query against them.

If you would like to reload from scratch then do like so.

```
make reload
dbt run
```

Then on, it is just rinse & spin with the dev process. You may rather want to use a better database [IDE](../dev/README.md) alternate at this point.
