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

## Requirements / Conditions

This expects certain infrastructure it exist in the warehouse target AWS account:
- terraform state bucket
- a VPC (name = UomPrimaryVpc)  # NOTE: preconfigured in account, not the same as defined in infra/vpc/ of this repo
- private subnets (tag:Network = Private)
- Security Groups (tag:Name = UomPrimaryVpcEndpoints)