# OrcaHouse Aurora PostgreSQL

The stack use terraform workspace.

```
terraform workspace list
  default
* dev
  prod
```

Login to corresponding AWS account and apply like so.

```
export AWS_PROFILE=umccr-dev-admin && terraform workspace select dev && terraform plan
terraform apply
```
