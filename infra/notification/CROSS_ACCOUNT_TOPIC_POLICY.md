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

## Statements to remove after the OrcaGlue cutover

Once the OrcaGlue rules and notify roles are deleted from the OrcaGlue `shared-infra`
Pulumi stack, ask the topic owners to remove the statements that allowed them. A statement
whose role was deleted no longer grants anything, and its principal shows as an unreadable
role ID.

| Env  | Sid                                   | Principal                                                                     |
| ---- | ------------------------------------- | ----------------------------------------------------------------------------- |
| dev  | `AllowOrcaGlueDevGlueFailureNotify`   | `arn:aws:iam::115253169271:role/orcaglue-shared-infra-glue-notify-role-dev`   |
| prod | `AllowOrcaGlueProdGlueFailureNotify`  | `arn:aws:iam::115253169271:role/orcaglue-shared-infra-glue-notify-role-prod`  |

## Encryption note

The AWS-managed `aws/sns` key cannot be used for cross-account publishing. Confirm
each topic's encryption state with its owner; if a customer-managed
key (CMK) is in use, the publisher role and the key policy also need
`kms:GenerateDataKey*` and `kms:Decrypt` on that key.
