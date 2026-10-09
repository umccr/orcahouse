# Notification Infrastructure

Sends failures of OrcaHouse warehouse processes in account `115253169271` to Slack.
EventBridge rules match failed Glue jobs, Glue crawlers and DMS tasks, turn them into
Amazon Q messages, and publish them to each environment's Slack SNS topic. Alerts that
cannot be delivered go to a dead-letter queue, and an alarm on that queue posts to the same
channel.

| Env  | Slack channel | Watches |
| ---- | ------------- | ------- |
| dev  | `alerts-dev`  | `orcaglue-dev-*` Glue jobs, crawler `orcavault-db-dev-mart-crawler` |
| prod | `alerts-prod` | `orcaglue-prod-*` Glue jobs, `orcabus-db` DMS instance and tasks, `orcabus-db-crawler-*` crawlers |

See [ARCHITECTURE.md](ARCHITECTURE.md) for the diagram, rules and design notes.

## Layout

```text
infra/notification/
  modules/publisher-role/      # IAM role that publishes to the Slack topic, SSM parameters
  modules/target-dlq/          # dead-letter queue, queue policy, DLQ alarm, SSM parameter
  modules/notification-rules/  # EventBridge rules and Slack targets
  environments/dev/            # dev root module
  environments/prod/           # prod root module
```

## Usage

```bash
export AWS_PROFILE=unimelb-warehouse-prod-admin
aws sso login

cd environments/<env>
terraform init
terraform plan
terraform apply
```

For the first deployment of an environment:

1. After the apply, ask the Slack topic owner to add the statement in
   [CROSS_ACCOUNT_TOPIC_POLICY.md](CROSS_ACCOUNT_TOPIC_POLICY.md). Until they do, alerts
   wait in the dead-letter queue.
2. Test the whole path. An alarm message should appear in `#alerts-<env>`, then a
   "Resolved" message about 5 minutes later:

   ```bash
   aws cloudwatch set-alarm-state --alarm-name orcahouse-notify-<env>-target-dlq-not-empty \
     --state-value ALARM --state-reason "Deployment test"
   ```

## Before merging

CI does not cover this stack. From the repository root:

```bash
terraform fmt -check -recursive infra/notification
(cd infra/notification/environments/dev && terraform init -backend=false && terraform validate)
(cd infra/notification/environments/prod && terraform init -backend=false && terraform validate)
```
