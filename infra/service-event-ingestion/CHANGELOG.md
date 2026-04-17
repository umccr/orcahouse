# Changelog

All notable changes to the `service-event-ingestion` module are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [Unreleased]

### Added — Variant Monitoring ingestion ([#212](https://github.com/umccr/orcahouse/issues/212))

Adds a full ingestion pipeline for `VariantMonitoringResult` events emitted by
[service-variant-monitoring](https://github.com/OrcaBus/service-variant-monitoring).

**`dev/src/psa.sql`**
- New table `orcavault.psa.event__variant_monitoring_result`.
  Captures all fields from the `VariantMonitoringResult` event detail
  ([schema](https://github.com/OrcaBus/service-variant-monitoring/blob/main/docs/events/VariantMonitoringResult/VariantMonitoringResult.schema.json)):
  `portal_run_id`, `workflow_name`, `workflow_version`, `library_id`, `subject_id`,
  `individual_id`, `giab_id`, `analysis_name`, `output_uri`.
  The `monitoring_sites` array (per-site allele frequencies) is stored as `jsonb`.

**`infra/service-event-ingestion/lambda/vm_event_handler/vm_event_handler.py`**
- New Lambda handler. Validates `source = orcabus.variantmonitoring` and
  `detail-type = VariantMonitoringResult`, flattens the payload, and inserts one row
  into `psa.event__variant_monitoring_result`. Insert is idempotent on `event_id`.

**`infra/service-event-ingestion/vm.tf`**
- New Terraform file. Wires the `ingest_pipe` module for the Variant Monitoring event
  pattern (`orcabus.variantmonitoring` / `VariantMonitoringResult`).

**`infra/service-event-ingestion/monitor.tf`**
- Added `vm_lambda` to the Lambda error alarm dimensions.
- Added `vm_sqs` to the DLQ alarm dimensions.

**`infra/service-event-ingestion/docs/service-guide.md`**
- New service guide covering the end-to-end ingestion architecture, the PSA layer
  conventions, and a step-by-step walkthrough for adding a new event type.

---

## Previous changes

Changes prior to this changelog being introduced are tracked in the
[git history](https://github.com/umccr/orcahouse/commits/main/infra/service-event-ingestion).
