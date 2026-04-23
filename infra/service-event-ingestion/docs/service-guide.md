# Service Event Ingestion — Service Guide

This document describes the `service-event-ingestion` module for someone new to the
OrcaHouse platform, Terraform, or event-driven architecture on AWS.

## 1. What This Module Does

OrcaBus services communicate by emitting events onto a shared AWS EventBridge bus
(`OrcaBusMain`). This module captures those events and persists them into the OrcaHouse
Vault PostgreSQL database.

The pattern is a lightweight form of **Change Data Capture (CDC)**:

- OrcaBus services are the source of truth for operational data.
- OrcaHouse is the analytical warehouse that needs a historical record of those events.
- This module is the bridge between them.

Each event type has its own Lambda function that:

1. Receives the event from EventBridge.
2. Extracts and flattens the fields.
3. Inserts one row into a PSA landing table in the database.

## 2. The Big Picture

```text
OrcaBus service (e.g. Workflow Manager)
  -> emits an event onto OrcaBusMain EventBridge bus
  -> EventBridge rule filters by source + detail-type
  -> Lambda function is invoked
  -> Lambda flattens the event payload
  -> Lambda inserts one row into the PSA table in OrcaVault (PostgreSQL)
  -> SQS Dead Letter Queue (DLQ) catches any failed invocations
```

The database insert is idempotent: if the same `event_id` is received twice, the second
insert is silently skipped (`WHERE NOT EXISTS`).

## 3. The PSA Layer

PSA stands for **Persistent Staging Area**. It is the data landing zone inside the
OrcaHouse Vault database.

PSA tables follow these conventions:

- All columns are `varchar` (or `jsonb` for nested structures).
- Every table carries `load_datetime` (when the row was inserted) and `record_source`
  (which service and event type produced it).
- Tables are named after the event they capture, e.g. `event__workflow_run_state_change`.
- There is no transformation at this layer — data is stored as received.

Downstream layers (ODS, TSA) apply business logic on top of the PSA data.

The PSA schema is defined in [dev/src/psa.sql](../../../dev/src/psa.sql).

## 4. Events Ingested

| Service | Event type | PSA table | Terraform file |
|---|---|---|---|
| Workflow Manager | `WorkflowRunStateChange` | `event__workflow_run_state_change` | `wfr.tf` |
| FASTQ Manager | `FastqStateChange` | `event__fastq_list_row_state_change` | `fqr.tf` |
| Sequence Run Manager | `SequenceRunStateChange` | `event__sequence_run_state_change` | `srm.tf` |
| Sequence Run Manager | `SequenceRunLibraryLinkingChange` | `event__sequence_run_library_linking_change` | `srm.tf` |
| Metadata Manager | `MetadataStateChange` | `event__metadata_state_change_library` | `mm.tf` |
| Variant Monitoring | `VariantMonitoringResult` | `event__variant_monitoring_result` | `vm.tf` |

## 5. AWS Resources Created Per Event Type

Each call to the `ingest_pipe` Terraform module (in `infra/common/ingest_pipe/`)
creates the following AWS resources:

### EventBridge rule

Listens to the `OrcaBusMain` event bus and filters by `source` + `detail-type`.
Only matching events are forwarded to the Lambda. No Lambda cold starts for unrelated
events.

### Lambda function

- Runtime: Python 3.13
- Packaged with `psycopg2` from a shared Lambda layer.
- Runs inside the VPC to reach the private OrcaVault RDS cluster.
- Environment variable `DB_SECRET_NAME` points to the Secrets Manager secret holding
  the database credentials.

### SQS Dead Letter Queue (DLQ)

If the Lambda fails (e.g. a malformed event, a transient DB error), the event is
moved to the DLQ after the configured retries. CloudWatch alarms monitor DLQ depth.

### IAM policies

- Read access to the Secrets Manager secret.
- Permission to send failed messages to the DLQ.
- VPC network interface access (required for Lambda-in-VPC).

### CloudWatch alarms

Defined in `monitor.tf`. Two alarm types cover all Lambda functions:

- **Error alarm** — fires when Lambda error count ≥ 1 in a 60-second period.
- **DLQ alarm** — fires when the DLQ receives ≥ 1 message.

Both alarms notify via the shared SNS → Chatbot → Slack pipeline.

## 6. Repository Structure

```text
infra/service-event-ingestion/
├── main.tf               # Provider, VPC data, Secrets Manager, psycopg2 Lambda layer
├── variables.tf          # Input variables (db_secret_name, vpc_tags)
├── monitor.tf            # CloudWatch alarms for all Lambda functions and DLQs
├── fqr.tf                # FASTQ Manager ingestion pipe
├── mm.tf                 # Metadata Manager ingestion pipe
├── srm.tf                # Sequence Run Manager ingestion pipes (two event types)
├── vm.tf                 # Variant Monitoring ingestion pipe
├── wfr.tf                # Workflow Manager ingestion pipe
├── lambda/
│   ├── utils/
│   │   └── utils.py      # Shared helpers: get_secret, get_db_connection, push_to_db
│   ├── fqr_event_handler/
│   │   └── fqr_event_handler.py
│   ├── mm_lib_event_handler/
│   │   └── mm_lib_event_handler.py
│   ├── srm_llc_event_handler/
│   │   └── srm_llc_event_handler.py
│   ├── srm_sc_event_handler/
│   │   └── srm_sc_event_handler.py
│   ├── vm_event_handler/
│   │   ├── vm_event_handler.py
│   │   └── test_local.py
│   └── wfm_event_handler/
│       └── wfm_event_handler.py
└── docs/
    └── service-guide.md  # This file
```

The shared `ingest_pipe` Terraform module lives in:

```text
infra/common/ingest_pipe/
├── main.tf       # Lambda, DLQ, IAM, EventBridge rule and target
└── variables.tf  # Module inputs
```

## 7. How a Lambda Handler Works

All handlers follow the same pattern. Using `vm_event_handler.py` as the example:

### Module-level initialisation

```python
DB_SECRET_NAME = os.environ["DB_SECRET_NAME"]
DB_CREDENTIALS = utils.get_secret(DB_SECRET_NAME, secretsmanager_client)
DB_CONNECTION = utils.get_db_connection(DB_CREDENTIALS)
```

The DB connection is established once when the Lambda container starts (cold start),
then reused across invocations. This avoids opening a new connection on every event.

### `handler(event, context)`

The Lambda entrypoint. Calls `parse_event` then `push_to_db`.

### `parse_event(event)`

Validates `detail-type` and `source`, then extracts the fields into a flat dictionary
whose keys match the PSA table columns. Nested objects (e.g. `monitoringSites`) are
serialised with `json.dumps`.

### `push_to_db(conn, sql, data)`

Defined in `utils.py`. Builds the parameterised INSERT from the dictionary keys and
executes it. The `WHERE NOT EXISTS` guard prevents duplicate rows.

## 8. How to Add a New Event Type

Follow these four steps (the Variant Monitoring handler is the worked example).

### Step 1 — Define the PSA table

Add a `CREATE TABLE IF NOT EXISTS` block to [dev/src/psa.sql](../../../dev/src/psa.sql).

Conventions:
- Table name: `event__<service>_<event_type>` in snake_case.
- All data columns: `varchar`.
- Nested/array fields: `jsonb`.
- Always include `event_id varchar`, `event_time varchar`, `load_datetime timestamptz`,
  `record_source varchar(255)`.

### Step 2 — Write the Lambda handler

Create `lambda/<name>_event_handler/<name>_event_handler.py`.

Copy the structure from an existing handler (e.g. `vm_event_handler.py`) and set:

```python
TABLE_NAME = "event__<your_table>"
DETAIL_TYPE = "<YourEventDetailType>"
EVENT_SOURCE = "orcabus.<yourservice>"
```

Implement `parse_event` to extract the fields from the EventBridge envelope into a
flat dict that maps to your table columns.

### Step 3 — Add the Terraform module call

Create `<service_abbreviation>.tf`:

```hcl
locals {
  <abbr> = {
    function_name = "<name>_event_handler"
  }
}

module "<abbr>_result" {
  source = "../common/ingest_pipe"

  service_id     = "<ABBR>"
  iam_path       = "/orcavault/serviceingestion/<abbr>/"
  db_secret_name = var.db_secret_name

  event_pattern = {
    detail-type = ["<YourEventDetailType>"]
    source      = ["orcabus.<yourservice>"]
  }

  lambda_function_name     = local.<abbr>.function_name
  lambda_function_handler  = "${local.<abbr>.function_name}.handler"
  lambda_source_paths      = [
    "lambda/${local.<abbr>.function_name}",
    "lambda/utils/utils.py"
  ]
  lambda_artefact_out_path = ".temp/lambda/${local.<abbr>.function_name}.zip"
  lambda_layers            = [aws_lambda_layer_version.psycopg2_layer.arn]
}
```

### Step 4 — Add CloudWatch alarms

In `monitor.tf`, add entries for the new Lambda to both alarm dimensions blocks:

```hcl
# in module "lambda_error_alarms"
"<abbr>_lambda" = {
  FunctionName = local.<abbr>.function_name
}

# in module "lambda_dlq_alarms"
"<abbr>_sqs" = {
  QueueName = "${local.<abbr>.function_name}_dlq"
}
```

## 9. Local Testing

A local PostgreSQL instance is available via Docker Compose in `dev/`.

### Start the database and create the PSA tables

```bash
cd dev
make up    # starts Postgres on localhost:5432
make psa   # runs psa.sql to create all PSA tables
```

### Run the handler test script

Each handler directory can contain a `test_local.py` script.

For the Variant Monitoring handler:

```bash
cd infra/service-event-ingestion/lambda/vm_event_handler
pip install psycopg2-binary
python test_local.py
```

The script patches out the AWS SDK calls (Secrets Manager) and connects directly
to the local Postgres. It runs three checks:

1. `test_parse_event` — asserts all fields are extracted correctly.
2. `test_db_insert` — inserts the parsed event and reads the row back.
3. `test_duplicate_insert` — verifies the idempotency guard keeps the count at 1.

### Connect to the local database directly

```bash
cd dev
make psql
# then in psql:
SELECT * FROM psa.event__variant_monitoring_result LIMIT 5;
```

## 10. Deployment

The module is deployed with Terraform.

```bash
cd infra/service-event-ingestion
terraform init
terraform workspace select <env>   # e.g. prod
terraform plan
terraform apply
```

After applying, run the PSA DDL against the target database to create any new tables
added to `psa.sql`.

## 11. Short Glossary

| Term | Meaning |
|---|---|
| CDC | Change Data Capture — capturing every state change in a source system |
| PSA | Persistent Staging Area — the raw landing zone in the warehouse |
| ODS | Operational Data Store — lightly transformed layer above PSA |
| EventBridge | AWS service that routes events between producers and consumers |
| DLQ | Dead Letter Queue — holds events that Lambda failed to process |
| ingest_pipe | Reusable Terraform module that wires EventBridge → Lambda → DLQ |
| OrcaBusMain | The shared EventBridge bus used by all OrcaBus platform services |
| record_source | Column tracking which service and event type produced each PSA row |
