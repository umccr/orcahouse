# Aurora PostgreSQL Warehouse

> NOTE: **DEPRECATED**
> 
> * This stack has been replaced by the [Redshift](../../../redshift) warehouse stack.
> * This stack will be taken down once the full migration is completed to the Redshift warehouse.

---

Login to corresponding AWS account and apply like so.

```
export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan
terraform apply
```

The stack use terraform workspace.

```
terraform workspace list
  default
* prod
```
