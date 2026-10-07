# Project Structure

OrcaHouse is a **monorepo**. Three concerns live side by side: Terraform infrastructure (`infra/`), the legacy PostgreSQL dbt project (`orcavault/`), and a local Postgres dev stack (`dev/`).

## Top-level layout

```
orcahouse/
├── infra/            # Terraform stacks + the mart GraphQL API (see below)
├── orcavault/        # Legacy dbt project (dbt-postgres): psa -> dcl -> mart
├── dev/              # Docker Compose local Postgres + DDL + sample-data loaders
├── Makefile          # Repo-wide: install / check / scan / baseline / test / test-iac
├── .pre-commit-config.yaml
├── .secrets.baseline # detect-secrets baseline
└── README.md         # Points to orcahouse-doc and orcahouse-user-stories
```

## `infra/` — Terraform stacks

Each subdirectory is an independent Terraform root module with its own backend and lifecycle. **There is no top-level Terraform that applies them all.** You `cd` into a stack and run `terraform` there.

Two generations of stacks coexist (see product.md and tech.md). The directory shape differs between them:

- **UMCCR-era stacks** (legacy, account `472057503814`/`843407916570`) use **Terraform workspaces** (`dev`/`prod`/`stg`) to drive per-environment maps.
- **Warehouse-era stacks** (new, account `115253169271`) use **one directory per environment** (`environments/dev`, `environments/prod`) and **no workspaces**.

Stacks (grouped by purpose):

```
infra/
├── api/                      # Mart GraphQL API: Terraform + lambda-server/ (TypeScript PostGraphile)
├── athena/
│   ├── legacy/               # LIVE federated Athena over legacy orcahouse-db (workgroup "orcahouse")
│   └── workgroup/            # Warehouse-account Athena workgroups (dev/prod) for the lake path
├── aurora/
│   └── environments/
│       ├── umccr-prod/       # LEGACY Aurora PG "orcahouse-db" (DEPRECATED label, still live)
│       ├── dev/ , prod/      # Warehouse-account Aurora "Data API backend" (consumer not yet wired)
├── aurora-su/                # Aurora DB users + Secrets Manager rotation (ro, athena, psa, tsa)
├── common/                   # Reusable modules: config, db_user, ingest_pipe
├── dms/orcabus-db/           # DMS CDC: OrcaBus Aurora -> S3 landing zone (Parquet)
├── ec2/
│   ├── account-wide/         # Warehouse account-wide SG rule + EC2 Instance Connect Endpoint
│   ├── umccr-mgmt/           # Legacy bastion (SSM / EICE tunnel to orcahouse-db)
│   └── warehouse-mgmt/       # Warehouse bastion (tunnel to Redshift)
├── ecs/orcavault-dbt/        # ECS Fargate task + EventBridge scheduler that runs the legacy dbt daily
├── glue/                     # LEGACY Glue spreadsheet/CSV jobs -> TSA (DEPRECATED -> OrcaGlue)
├── glue-crawler/
│   ├── orcabus-db/           # Crawl CDC landing zone -> Glue DBs orcabus_<db>
│   └── orcavault-db/         # Crawl Redshift UNLOAD output -> Glue DB orcavault_<env>_mart
├── lakeformation/
│   └── environments/
│       ├── warehouse/        # LF producer: registered locations, internal + RAM cross-account grants
│       └── umccr-prod/       # LF consumer: resource links (mart, result)
├── redshift/                 # Redshift Serverless (modules/redshift-serverless), environments dev/prod
├── s3/                       # Lake buckets: landing-zone, orcavault, oncovault, cache, pulumi-state
├── service-event-ingestion/  # EventBridge -> Lambda -> PSA event__* tables (6 ingest pipes)
└── vpc/                      # endpoint-services (PrivateLink, IN USE), peer / transit-gateway / warehouse-vpc (NOT in use)
```

Notes on `infra/`:
- `infra/api/lambda-server/` is a standalone pnpm/TypeScript project (the PostGraphile server bundled into the Lambda zip). It has its own `package.json`, `pnpm-lock.yaml`, and `tsconfig.json`.
- `infra/common/` holds reusable child modules, not a deployable stack: `config` (shared constants, VPC/SG lookups), `db_user` (one Secrets Manager user + rotation), `ingest_pipe` (one EventBridge rule + Lambda for an ingest service).
- The PrivateLink stack `infra/vpc/endpoint-services/orcabus-db` is the connectivity actually in use between the warehouse account and the OrcaBus DB. `peer-main-vpc`, `transit-gateways`, and `warehouse-vpc` are present but **not deployed** (SCP-blocked or pivoted away from) — their READMEs say so. Do not revive them without confirming.

## `orcavault/` — legacy dbt project (dbt-postgres)

Standard dbt layout. Schemas map 1:1 to warehouse layers via a custom `generate_schema_name` macro (the configured schema name is used verbatim, no target prefix).

```
orcavault/
├── dbt_project.yml       # profile "orcavault"; psa/dcl/mart -> table; default view; seeds -> dcl
├── profiles.yml          # dev (localhost) + prod (host/user/password from DBT_ENV_SECRET_* env)
├── packages.yml          # dbt_utils
├── models/
│   ├── psa/              # 3 incremental models + sources.yml (ods, legacy, tsa, psa sources)
│   ├── dcl/              # Data Vault 2.0: hubs, links, satellites, effsats, SALs + *_schema.yml (enforced contracts)
│   └── mart/             # Consumer marts, grouped by team folder (centre, curation, dawson, tothill, ...)
├── macros/              # extract_* ID parsers, grant_select, generate_schema_name, parse_ica_cost_metadata
├── seeds/
│   └── dictionary/      # dictionary__data_mart_catalog.csv (STABLE/DEMO per mart) + mdm__workflow_run
├── analyses/ snapshots/ tests/   # .gitkeep only (no dbt data tests defined)
└── Makefile             # Proxies dev/ targets + `doc` (dbt docs generate)
```

Layer/writer map (who populates each schema in prod):
- `legacy`, `ods` — populated outside this repo (docs describe FDW read-only mounts; not defined in code).
- `tsa` — written by the legacy Glue jobs (`infra/glue/`).
- `psa` — `event__*` tables written by the ingest Lambdas (`infra/service-event-ingestion/`); spreadsheet/ICA tables built by dbt.
- `dcl`, `mart` — built by dbt. `mart` also gets `public.*` alias views via the `grant_select` macro.

## `dev/` — local Postgres stack

Docker Compose Postgres for developing `orcavault/` locally. The DDL files mirror the prod schemas that are not dbt-managed.

```
dev/
├── compose.yml      # single postgres:16.4 service, port 5432, mounts src/ + data/
├── Makefile         # up/down/psql, legacy|ods|tsa|psa (apply DDL), all, load, next, reload, sync
├── src/
│   ├── init.sql     # creates user "dev" + database "orcavault"
│   ├── legacy.sql   # legacy.data_portal_* tables
│   ├── ods.sql      # ods.* tables (mirror OrcaBus service DBs)
│   ├── tsa.sql      # tsa.* tables + tsa.truncate_tables()
│   ├── psa.sql      # psa event__* + cost + spreadsheet tables (source of truth for ingest DDL)
│   └── load.sh / next.sh   # \copy sample CSVs from data/
├── data/            # sample CSVs (gitignored except .gitkeep); populated via `make sync` from S3
└── requirements.txt # dbt-core, dbt-postgres (unpinned)
```

The local dev loop: `make reload` in `dev/` (down → up → apply all DDL → load CSVs), then run dbt from `orcavault/` against localhost.

## `.agents/` and `.kiro/`

- `.agents/tasks/` holds research artifacts and task notes for agent work (e.g. the fact inventory used to author these steering files).
- `.kiro/steering/` holds these steering docs. Steering files can include other repo files by reference when extra context is needed.

## Conventions

- **Schema names are literal** (`psa`, `dcl`, `mart`, `tsa`, `ods`, `legacy`) and map to warehouse layers. Don't invent new schema names without a layering reason.
- **dbt model naming** follows Data Vault 2.0: `hub_*`, `link_*`, `sat_*`, `effsat_*`, `sal_*` in DCL; mart tables are grouped into team subfolders under `models/mart/`.
- **DCL models declare enforced contracts** (`contract: { enforced: true }`) with typed columns and PK constraints in the per-folder `*_schema.yml`. Keep contracts in sync when changing a model's columns.
- **Terraform region is `ap-southeast-2` everywhere.** Standard default tags are `umccr-org:Product=OrcaHouse`, `umccr-org:Creator=Terraform`, `umccr-org:Service=OrcaHouse`, `umccr-org:Source=<repo url>`.
