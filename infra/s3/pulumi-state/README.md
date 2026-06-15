# Warehouse Pulumi State Backend

This stack provisions infrastructure resources, a S3 bucket and KMS key for Pulumi state backend.

Pulumi, an iterative (and imperative programming) IaC toolchain is chosen to provision [OrcaGlue](https://github.com/umccr/orcaglue) ETL job pipelines in a modern micro-app dev stack deployment fashion.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```
