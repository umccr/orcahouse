# Orcahouse API

This Terraform module deploys a PostGraphile server on AWS Lambda, accessible via the custom domain `mart.prod.umccr.org`. The server automatically introspects the configured PostgreSQL schema, as defined in the `main.tf` locals and variables.

The module exposes a `db_name` variable to specify the target database name for the Lambda function to connect to, using the provided user credentials.

## Deployment

Before deploying, ensure the Lambda server asset is built at `./lambda-server/dist/index.zip`. To build the Lambda asset:

```sh
cd lambda-server
pnpm install
pnpm build
```

Then, with your production AWS credentials configured, deploy using Terraform:

```sh
terraform init
terraform workspace select prod
terraform plan -var-file="orcavault.tfvars"
terraform apply -var-file="orcavault.tfvars"
```

## PostGraphile Lambda Server

This project deploys a GraphQL server using PostGraphile v5, which introspects a PostgreSQL schema and automatically generates a GraphQL endpoint.

While PostGraphile v5 is still in beta, it currently supports integration with Fastify v4 and is considered suitable for production use. In our case, the server is used in a read-only capacity, and API authentication is managed through an API Gateway authorizer.

### AWS Lambda Handler

The Lambda function expects the following environment variables:

- `DATABASE_NAME` – The name of the PostgreSQL database to connect to.
- `SECRET_ARN` – The ARN of the AWS Secrets Manager secret containing the database credentials.
- `GRAPHILE_ENV` – Specifies the environment stage (development or production).
