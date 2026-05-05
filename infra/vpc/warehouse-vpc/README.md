# warehouse-vpc

```
export AWS_PROFILE=unimelb-warehouse-prod-owner

terraform plan
terraform apply
```

Notes:
* Uses the terraform module from https://github.com/terraform-aws-modules/terraform-aws-vpc
* Requires a platform owner
* Does not use terraform workspace
* Uses the central terraform state bucket for state storage and locking
