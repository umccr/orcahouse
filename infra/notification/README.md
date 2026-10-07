# Notification Infrastructure

Foundation for the OrcaHouse warehouse notification system.

This stack provisions **only** the publisher-role + SSM-parameter foundation.

The `dev` and `prod` environments are managed separately for isolation and share
the `modules/publisher-role` module.

## Layout

```
infra/notification/
  modules/publisher-role/   # shared role + inline policy + SSM parameters
  environments/dev/         # dev stack (account 115253169271)
  environments/prod/        # prod stack (account 115253169271)
```

## Per-environment resources

Each environment creates (with `<env>` = `dev` or `prod`):

- **IAM role** `orcahouse-notify-<env>-publisher-role` — trusted by `events.amazonaws.com`. The trust policy applies confused-deputy protection:
  - `StringEquals` on `aws:SourceAccount` = `115253169271`
  - `ArnLike` on `aws:SourceArn` = `arn:aws:events:ap-southeast-2:115253169271:rule/orcahouse-notify-<env>-*`
- **Inline policy** `orcahouse-notify-<env>-publisher-role-inline-policy` — allows only `sns:Publish` on that environment's Slack topic. No KMS permissions are granted; the Slack topics are treated as unencrypted / not customer-managed-key. If a topic were encrypted with a CMK, the role would also need `kms:GenerateDataKey*` and `kms:Decrypt` on that key.
- **SSM parameters** (type `String`):
  - `/orcahouse/notification/<env>/slack_topic_arn`
  - `/orcahouse/notification/<env>/publisher_role_arn`

## Usage

```
export AWS_PROFILE=unimelb-warehouse-prod-admin
aws sso login
```

### dev

```
cd environments/dev
terraform init
terraform plan
terraform apply
```

### prod

```
cd environments/prod
terraform init
terraform plan
terraform apply
```

## Verification (local — CI does not cover this stack)

CI does not run against this stack, so `terraform fmt` and `terraform validate`
must be run locally before merging:

```
terraform fmt -check -recursive infra/notification

cd infra/notification/environments/dev  && terraform init -backend=false && terraform validate
cd infra/notification/environments/prod && terraform init -backend=false && terraform validate
```
