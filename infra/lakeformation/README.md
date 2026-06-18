# LakeFormation Infrastructure

See the [system design document](https://github.com/umccr/orcahouse-doc/tree/main/arch) for high-level architecture.

The production grade LakeFormation infrastructure for the Data Warehouse project.

The LakeFormation takes care of data mart tables sharing to the consumer environments.

The LakeFormation is capable of enforcing data tables permissions all the way down to the cell level.

For a given data policy, LakeFormation can be setup at levels:
- Database
- Table
- Column
- Row
- Cell

The environments are managed separately for isolation.

Do like so.

## Warehouse Environment

```
export AWS_PROFILE=unimelb-warehouse-prod-admin
```

```
cd environments/warehouse
```

```
terraform init
terraform plan
terraform apply
```

## Consumer Environment

### umccr-prod

```
export AWS_PROFILE=umccr-prod-admin
```

```
cd environments/umccr-prod
```

```
terraform init
terraform plan
terraform apply
```
