# Notification Architecture

Sends failures of OrcaHouse warehouse processes to Slack. All resources live in the
warehouse account `115253169271`. `dev` and `prod` are separate Terraform roots that post
to separate channels.

```text
┌─ Warehouse account 115253169271 (ap-southeast-2) ──────────────────────┐
│   Glue jobs     Glue crawlers     DMS tasks       CloudWatch alarms    │
│       │               │               │                   │            │
│       └───────────────┴───────┬───────┴───────────────────┘            │
│                               │ state-change events                    │
│                               ▼                                        │
│                 EventBridge default event bus                          │
│                               │                                        │
│                               ▼                                        │
│                Rules orcahouse-notify-<env>-*                          │
│     match a failure, reshape it into an Amazon Q message               │
│                │                                 │                     │
│                │ as the publisher role           │ if delivery fails   │
│                │                                 ▼                     │
│                │                       SQS dead-letter queue           │
│                │                                 │                     │
│                │                                 ▼                     │
│                │                  alarm ...-target-dlq-not-empty       │
│                │                  (a CloudWatch alarm: forwarded       │
│                │                  to Slack like any other alert)       │
└────────────────┼───────────────────────────────────────────────────────┘
                 │ sns:Publish (cross-account)
                 ▼
┌─ Slack topic account: dev 843407916570, prod 472057503814 ─┐
│   SNS AwsChatBotTopic-alerts  ──►  Amazon Q Developer      │
└────────────────────────────────────────┬───────────────────┘
                                         ▼
                                Slack #alerts-<env>
```

## Rules

| Key | Env | Fires when |
| --- | --- | ---------- |
| `glue-job-failure` | dev, prod | An `orcaglue-<env>-*` Glue job ends `FAILED` or `TIMEOUT` |
| `crawler-failed`, `crawler-start-failed` | dev, prod | A listed crawler fails, or its scheduled start fails |
| `dms-<identifier>` | prod | A DMS instance or task reports `Failure` or `LowStorage`, or a task stops |
| `orcavault-run-failed` | dev, prod | An OrcaVault dbt run in this environment ends `failed` |
| `orcavault-run-warned` | dev, prod | An OrcaVault dbt run in this environment ends `warned`: models were applied, but warn-severity tests failed |
| `orcavault-run-error` | dev, prod | An OrcaVault dbt run in this environment ends `error` or `skipped` |
| `orcavault-sources-degraded` | dev, prod | The OrcaVault sources stage ends `degraded`: a DMS task wasn't running, or a crawl didn't succeed. Publish has nothing to fail yet, so only its `error` is alerted |
| `orcavault-sources-error`, `orcavault-publish-error` | dev, prod | The OrcaVault stage before or after the run ends `error` |
| `alarm-firing`, `alarm-resolved` | dev, prod | An `orcahouse-notify-<env>-*` or `orcavault-run-<env>-*` alarm enters `ALARM` or returns to `OK` |

Watched crawlers and DMS resources are listed in `environments/<env>/main.tf`. The
OrcaVault rules match the `OrcaVaultRunFinished`, `OrcaVaultSourcesFinished` and
`OrcaVaultPublishFinished` events that
[infra/orcavault-run](../orcavault-run/README.md#the-run-event) sends. The
`orcavault-run-<env>-*` alarms include the sources and publish stages' alarms.

## Notes

- **Naming:** the publisher role trusts only rules named `orcahouse-notify-<env>-*`, so the
  topic owner allows one role per environment
  ([CROSS_ACCOUNT_TOPIC_POLICY.md](CROSS_ACCOUNT_TOPIC_POLICY.md)).
- **No free text:** EventBridge inserts values unescaped, so messages never include error
  text. Alarm descriptions must have no double quotes; `\n` marks a line break. The
  OrcaVault events are the exception: the run's runner writes `error`, `failedNodes` and
  `warnedNodes` on one line without double quotes or backslashes, and the sources and
  publish stages only list crawler and DMS task names with their states, or their own fixed
  messages.
- **Duplicates:** a failed crawler that the sources stage started has its own alert, and
  also makes the stage `degraded`, which says that the run went ahead without it.
- **DMS stops:** stopping a task on purpose, such as to change an endpoint, alerts too.
  Mute it for the maintenance window with `disabled_notification_rules`.
- **Environment:** dev and prod OrcaVault runs send to the same default bus, so the run
  rules match `detail.environment`.
- **DMS:** ARNs end in a generated ID, so there is one rule per resource, matched by ARN.
  After a task or instance is replaced, re-apply prod.
- **Limit:** if every publish to the Slack topic fails, the DLQ alarm cannot reach Slack
  either. Undelivered alerts stay in the DLQ for 14 days.
