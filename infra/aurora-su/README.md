# aurora-su

> TIP: _think of it like Unix `su`_

Aurora db service user (su) stack. The stack use terraform workspace.

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

New user provisioning is just replica of existing TF script. Naming convention is loosely `<database>_<schema>.tf`. 

As follows.

```
cp orcavault_tsa.tf orcavault_psa.tf
vi orcavault_psa.tf
```

Then follow by TF plan & apply^^, etc.
