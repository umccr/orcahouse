# Manual step: cross-account Slack topic policy

The Slack SNS topics (`AwsChatBotTopic-alerts`) live in other AWS accounts, so the
publisher roles created by this stack cannot be granted access from here. After the
stack is applied, the **topic owners** must add one statement per role to each
topic's access policy (same pattern as was done for OrcaGlue).

## Topics

| Env  | Topic account    | Slack topic ARN                                                   |
| ---- | ---------------- | ----------------------------------------------------------------- |
| dev  | `843407916570`   | `arn:aws:sns:ap-southeast-2:843407916570:AwsChatBotTopic-alerts`  |
| prod | `472057503814`   | `arn:aws:sns:ap-southeast-2:472057503814:AwsChatBotTopic-alerts`  |

## Statements to add

Dev topic (account `843407916570`):

```json
{
  "Sid": "AllowOrcaHouseDevNotify",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::115253169271:role/orcahouse-notify-dev-publisher-role" },
  "Action": "sns:Publish",
  "Resource": "arn:aws:sns:ap-southeast-2:843407916570:AwsChatBotTopic-alerts"
}
```

Prod topic (account `472057503814`):

```json
{
  "Sid": "AllowOrcaHouseProdNotify",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::115253169271:role/orcahouse-notify-prod-publisher-role" },
  "Action": "sns:Publish",
  "Resource": "arn:aws:sns:ap-southeast-2:472057503814:AwsChatBotTopic-alerts"
}
```

## Encryption note

The AWS-managed `aws/sns` key cannot be used for cross-account publishing. Confirm
each topic's encryption state with its owner (issue note U-11); if a customer-managed
key (CMK) is in use, the publisher role and the key policy also need
`kms:GenerateDataKey*` and `kms:Decrypt` on that key.
