# FIXME

* SCP denied for `ec2:AcceptVpcP*`, `ec2:CreateVpcP*`, `ec2:ModifyVpcP*` at unimelb side.
* https://umccr.slack.com/archives/C02DV6G54DN/p1777609626140329
* https://umccr.slack.com/archives/DN533CY5T/p1777856982272419
* This stack has been `terraform destroy` and _NOT IN USE_ for now.



---



# VPC Peering with main-vpc

This establishes [VPC peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html) between Warehouse account and Application account.

```
   Warehouse Account                 Application Account
┌───────────────────┐                ┌─────────────────┐
│  warehouse-vpc    │                │  main-vpc       │
│  172.29.0.0/18    │◄──── pcx ─────►│  10.2.0.0/16    │
│                   │   Peering Conn │                 │
└───────────────────┘                └─────────────────┘
```

## Terraform

```
export AWS_PROFILE=unimelb-warehouse-prod-owner

terraform plan
terraform apply
```
