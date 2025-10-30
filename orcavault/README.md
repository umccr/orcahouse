# OrcaVault

OrcaVault is a dbt project. It contains data warehouse models.

## Local Development

- See [dev/README](../dev/README.md) for local dev setup and prerequisites.

```
make up
make ps
make all
make psql
orcavault=> \l
orcavault=> \dn
orcavault=> \dn tsa
orcavault=> set search_path to tsa;
orcavault=> \dt
orcavault=> \d spreadsheet_library_tracking_metadata
orcavault=> select count(1) from spreadsheet_library_tracking_metadata;
orcavault=> set search_path to psa;
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
dbt seed
dbt run
```

```
make psql
orcavault=> set search_path to dcl;
orcavault=> \dt
orcavault=> \d hub_library
orcavault=> select count(1) from hub_library;
orcavault=> \q
```

## Make Load

To this point, it is good enough to work with structural changes and transformation from a previous section; i.e., data model development purpose. If you would like to try the ELT process with snapshot test data, you can sync from dev bucket. Steps are as follows.

```
export AWS_PROFILE=umccr-dev-admin
make sync
make down
make up
make all
make load
```

Now. Observe the tables from schema `ods` `tsa` and make some query. 

Next. Run `dbt` transformation.

```
dbt test
dbt build
dbt seed
dbt run
```

After dbt has run, observe the tables created in schema `psa` `dcl`. Make some query against them.

If you would like to reload from the start, then do like so.

```
make reload
dbt seed
dbt run
```

Then on, it is just rinse and spin with the local dbt dev process. You may rather want to use a better database [IDE](../dev/README.md) alternate at this point; instead of `psql` CLI.

## Hooks

See dbt documentation for post-ELT hook to perform dbt run operation [macros](macros).
- https://docs.getdbt.com/docs/build/hooks-operations
- https://docs.getdbt.com/reference/commands/run-operation

e.g.
```
export RO_USERNAME=dev
dbt run-operation grant_select --args "{role: $RO_USERNAME}" --target dev
```
