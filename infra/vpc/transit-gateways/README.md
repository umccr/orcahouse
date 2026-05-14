# FIXME

* SCP denied for `ec2:CreateTran*` at unimelb side.
* This stack has been `terraform destroy` and _NOT IN USE_ for now.



---



# Data Warehouse Transit Gateway

This stack creates a transit gateway as the hub for the data warehouse.
It allows connecting to other accounts VPC to the warehouse hub.

* Requires sso login session for both accounts.

```
export AWS_PROFILE=umccr-prod-admin
aws sso login

export AWS_PROFILE=unimelb-warehouse-prod-admin
aws sso login
```

* The terraform state is stored at the `unimelb-warehouse-prod` account side. Apply like so.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

Using transit gateway module from:

* https://registry.terraform.io/modules/terraform-aws-modules/transit-gateway/aws/latest
* https://github.com/terraform-aws-modules/terraform-aws-transit-gateway
* https://github.com/terraform-aws-modules/terraform-aws-transit-gateway/tree/master/examples/multi-account
