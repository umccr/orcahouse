# Redshift Infrastructure

The production grade Redshift Serverless infrastructure for the Data Warehouse project.

The `dev` and `prod` environments are managed separately for isolation.

Do like so.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin
```

## dev

```
cd environments/dev

terraform init
terraform plan
terraform apply
```

## prod

```
cd environments/prod

terraform init
terraform plan
terraform apply
```
