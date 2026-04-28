# Changelog

All notable changes to the `service-event-ingestion` module are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

---

## [Unreleased]

### Added — Variant Monitoring DCL satellite ([#215](https://github.com/umccr/orcahouse/issues/215))

Builds the DCL layer satellite for variant monitoring results on top of the PSA table from #212.

**`orcavault/models/dcl/sat_variant_monitoring_result.sql`**

- New multi-active satellite on `link_library_workflow_run`. Reads from
  `psa.event__variant_monitoring_result`, computes `library_workflow_run_hk =
  SHA256(workflow_run_hk || library_hk)` and `hash_diff = SHA256(chrom, pos, ref, alt,
  dp, af, filter_status, variant_emitted)`. One row per monitoring site, append strategy,
  idempotent on `(library_workflow_run_hk, hash_diff)`.

**`orcavault/models/dcl/sat_schema.yml`**

- Contract with PK `(library_workflow_run_hk, hash_diff, load_datetime)` and FK to
  `link_library_workflow_run`.

**`orcavault/models/psa/sources.yml`**

- Registered `event__variant_monitoring_result` as a dbt PSA source.

**`dev/src/load.sh`**

- Added `\copy psa.event__variant_monitoring_result` so `make reload` seeds the PSA table from
  `dev/data/orcavault_psa_event__variant_monitoring_result.csv` (synced from S3 via `make sync`).
  The CSV contains a real `VariantMonitoringResult` event (smoke-test run `20260315ff1641fe` / `L2301217`,
  10 monitoring sites, emitted by `variant-monitoring-extract-variant-af-beta` on 2026-04-23).

---

### Added — Variant Monitoring ingestion ([#212](https://github.com/umccr/orcahouse/issues/212))

Adds a full ingestion pipeline for `VariantMonitoringResult` events emitted by
[service-variant-monitoring](https://github.com/OrcaBus/service-variant-monitoring).

**`dev/src/psa.sql`**

- New table `orcavault.psa.event__variant_monitoring_result`.
  Flattened one row per monitoring site. Columns: `event_id`, `event_time`,
  `portal_run_id`, `library_id`, `chrom`, `pos`, `ref`, `alt`, `dp`, `af`,
  `filter_status`, `variant_emitted`, `load_datetime`, `record_source`.
  Unique constraint on `(portal_run_id, chrom, pos, ref, alt)`.

**`infra/service-event-ingestion/lambda/vm_event_handler/vm_event_handler.py`**

- New Lambda handler. Validates `source = orcabus.variantmonitoring` and
  `detail-type = VariantMonitoringResult`, fans out one row per entry in
  `monitoringSites`, and inserts into `psa.event__variant_monitoring_result`.
  Insert is idempotent on `(portal_run_id, chrom, pos, ref, alt)`.

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
