# Product

OrcaHouse — the UMCCR Enterprise Data Warehouse (EDW) project.

Reference architecture, glossary, and background docs live at https://github.com/umccr/orcahouse-doc. User stories live at https://github.com/umccr/orcahouse-user-stories. This repo (`README.md`) points to both.

## What OrcaHouse is

OrcaHouse is the data-warehouse program that captures, consolidates, history-tracks, and serves data from upstream **OrcaBus** — an event-driven estate of many small transactional microservice databases. The goal is business intelligence and an audit trail: capture change, consolidate it, observe it, archive it, and expose it for query and reporting.

**OrcaVault** is the first EDW under OrcaHouse. It serves the OrcaBus domain.

This repo is a **monorepo** holding three things:
- `infra/` — the warehouse infrastructure (Terraform, plus the mart GraphQL API).
- `orcavault/` — the **legacy PostgreSQL dbt project** that builds the `psa` → `dcl` → `mart` layers.
- `dev/` — a Docker Compose local Postgres stack for developing that dbt project.

## Warehouse layering (vocabulary)

Use these terms verbatim; they come from `orcahouse-doc/glossary.md` and drive schema names:

- **Staging Area Layer**: ODS (Operational Data Store, read-only mounts of frontline DBs) and TSA (Transient Staging Area, non-RDBMS sources like spreadsheets/CSV).
- **Enterprise Data Warehouse Layer**: PSA (Persistent Staging Area) and DCL (Data Consolidation Layer). DCL applies Data Vault 2.0 — Raw Vault and Business Vault (HUB, LNK, SAT, EFFSAT, SAL).
- **Information Delivery Layer**: DM (Data Mart) and IM (Information Mart).

The dbt schemas are literally `psa`, `dcl`, `mart`. Standard DV2 columns: `LDTS` (load date timestamp), `RSRC` (record source), hash keys.

## Two generations — read this before touching anything

OrcaHouse is mid-migration across two architectures and two sets of AWS accounts. Both exist in this repo at once.

1. **Legacy path (PostgreSQL, UMCCR prod account `472057503814`) — this is the LIVE serving path.**
   - Legacy Aurora PostgreSQL cluster `orcahouse-db` (database `orcavault`).
   - The `orcavault/` dbt project (dbt-postgres) runs daily on ECS Fargate against it.
   - The only mart GraphQL API (`infra/api`, `mart.prod.umccr.org`) and the only live Athena catalog (`infra/athena/legacy`) read its `mart` schema.
   - Several READMEs here mark `dev/`, `orcavault/`, `infra/glue/`, and `infra/aurora/environments/umccr-prod/` as DEPRECATED. **They are deprecated in intent but still in production.** Do not treat "deprecated" as "dead." The legacy stack is what currently feeds the UI, the API, and Athena.

2. **New warehouse path (Redshift + data lake, UniMelb warehouse account `115253169271`) — the migration target.**
   - OrcaBus Aurora → DMS CDC → S3 landing zone (Parquet) → Glue crawlers → Redshift Serverless (`orcavault` DB).
   - The Redshift rebuild of the dbt project lives in the **sibling `umccr/orcavault` repo** (dbt-redshift), not here.
   - Non-RDBMS sourcing (spreadsheets/CSV → TSA) is moving to the **sibling `umccr/OrcaGlue` repo** (Pulumi + Glue), replacing `infra/glue/` here.
   - Marts are published back to S3 (Parquet) and shared cross-account via Lake Formation.

When a change touches "the warehouse," always establish **which generation and which account** it belongs to first.

## Downstream consumers

- **OrcaHouse UI** (`umccr/orcahouse-ui`): a static Next.js app at `https://portal.umccr.org/orcahouse/` that queries the mart GraphQL API with a Cognito JWT.
- **Mart GraphQL API** (`infra/api`): PostGraphile on Lambda, exposing the `mart` schema read-only at `mart.prod.umccr.org`.
- **Athena**: federated query over the legacy mart (`orcavault.mart.<table>`), and warehouse-account workgroups for the dbt-redshift / lake path.

## Mart catalogue and maturity

Marts are tagged **STABLE** or **DEMO** in `orcavault/seeds/dictionary/dictionary__data_mart_catalog.csv`. The UI mirrors this. Treat STABLE marts as consumer-facing contracts; DEMO marts are provisional. The legacy repo currently publishes more marts than the Redshift rebuild — parity is a work in progress, so do not assume a mart that exists in one generation exists in the other.

## Sibling repos (context, not in this repo)

- `umccr/orcavault` — the Redshift/dbt-redshift rebuild of the dbt project.
- `umccr/OrcaGlue` — Pulumi-deployed Glue ETL for TSA sourcing (successor to `infra/glue/`).
- `umccr/orcahouse-doc` — architecture, glossary, ERDs, generated dbt docs.
- `umccr/orcahouse-ui` — the consumer UI.
