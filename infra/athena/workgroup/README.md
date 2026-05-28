# Athena Workgroup

This stack creates Athena workgroups for OrcaHouse in general.

The developer may still choose to use the default managed workgroup name `primary`.

However. This stack's workgroups are essentially needed for the dbt-athena adapter to run queries.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```
