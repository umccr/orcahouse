# VPC Endpoint Service for orcabus-db

This stack creates a VPC endpoint service for `orcabus-db`. It establishes the (cross-accounts) private connection between the data warehouse and the Aurora PostgreSQL database via AWS PrivateLink.

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

## Usage

Use the consumer side VPC endpoint interface `vpce_dns_names` output to connect to the database.

```
terraform output
```

Test the connection by running the following command at the consumer side with the EC2 instance in private subnet.
```
# Replace with endpoint DNS name
nc -vz <vpce-dns-name>.vpce.amazonaws.com 5432
```

## Architecture

* https://aws.amazon.com/blogs/database/access-amazon-rds-across-aws-accounts-using-aws-privatelink-network-load-balancer-and-amazon-rds-proxy/
* https://aws.amazon.com/blogs/compute/architecture-patterns-for-consuming-private-apis-cross-account/
* https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-share-your-services.html
