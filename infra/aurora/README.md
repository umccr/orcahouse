# OrcaHouse Aurora PostgreSQL

The stack use terraform workspace.

```
terraform workspace list
  default
* prod
```

Login to corresponding AWS account and apply like so.

```
export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan
terraform apply
```
