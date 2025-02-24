# OrcaHouse Athena

See https://docs.aws.amazon.com/athena/latest/ug/federated-queries.html

To establish another federated Data Source for OrcaHouse Athena, just simply replicate `orcavault.tf` and adjust the setup accordingly.

Like so.

```
cp orcavault.tf anothervault.tf
```

The stack uses terraform workspace.

```
terraform workspace list
  default
* prod
```

```
export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan
terraform apply
```
