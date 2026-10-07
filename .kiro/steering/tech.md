# Tech Stack & Conventions

OrcaHouse spans infrastructure-as-code, a dbt transformation project, and a TypeScript API. Region is **`ap-southeast-2`** everywhere.

## Infrastructure — Terraform

- Each `infra/<stack>/` is an independent root module with its own S3 backend. There is no umbrella root; `cd` into a stack to run `terraform`.
- **Two generations with different conventions** (see product.md):
  - **UMCCR-era** (account `472057503814`/`843407916570`): state bucket `umccr-terraform-states`, DynamoDB lock table `terraform-state-lock`, `required_version >= 1.10.0`, **AWS provider 5.91.0**, and **Terraform workspaces** (`dev`/`prod`/`stg`) driving per-env maps keyed by `terraform.workspace`. VPC looked up by tags `Name=main-vpc, Stack=networking, Environment=<workspace>`. Deploy: `terraform workspace select <env>` then `plan`/`apply`.
  - **Warehouse-era** (account `115253169271`): state bucket `terraform-states-363226301494-ap-southeast-2-an` (key prefix `115253169271/orcahouse/<path>/`), `use_lockfile = true` + `encrypt = true`, `required_version >= 1.15.0`, **AWS provider 6.x** (6.42–6.45), and **no workspaces** — one directory per environment under `environments/`. Network is the pre-existing `UomPrimaryVpc` (subnets `tag:Network=Private`, SG `UomPrimaryVpcEndpoints`).
- Match the generation you're in: don't add a workspace to a warehouse-era stack, and don't add an `environments/<env>` directory to a UMCCR-era stack.
- Terraform is installed via `infra/Brewfile` (`hashicorp/tap/terraform`).
- Standard default tags: `umccr-org:Product=OrcaHouse`, `umccr-org:Creator=Terraform`, `umccr-org:Service=OrcaHouse`, `umccr-org:Source=https://github.com/umccr/orcahouse`.
- Only two stacks are validated in CI (`infra/ec2/umccr-mgmt`, `infra/ec2/warehouse-mgmt`, via `make test-iac` with mock providers). Other stacks are not fmt/validate-checked by CI — run `terraform fmt`/`validate` yourself before committing IaC changes.

### Known IaC gaps (don't "fix" without checking)
- Some stacks are missing `.terraform.lock.hcl` (`infra/glue-crawler/orcavault-db/environments/prod`, `infra/vpc/peer-main-vpc`).
- Unpinned by design or by oversight: `terraform-aws-modules/lambda/aws` and the transit-gateway module (no version), the CI Terraform version, the ECS image tag (`:latest`). Pin deliberately, not reflexively.

## Transformation — dbt (legacy PostgreSQL project `orcavault/`)

- **dbt-core + dbt-postgres** (unpinned in `dev/requirements.txt`; published docs were generated with 1.11.8). The ECS prod image also installs them unpinned.
- Profile `orcavault`. `profiles.yml` targets: `dev` (localhost Postgres, the default) and `prod` (host/user/password from env `DBT_ENV_SECRET_HOST/USER/PASSWORD`).
- Materializations: default `view`; `psa`/`dcl`/`mart` → `table`; seeds → `dcl` schema.
- Custom `generate_schema_name` macro uses the configured schema name **verbatim** (no target-schema prefix) — that's why schemas are literally `psa`/`dcl`/`mart`.
- **Data Vault 2.0 patterns in DCL**: hubs/links are incremental `merge` on the hash key; most satellites are incremental `append`; effectivity satellites merge on `hash_diff`. Hash keys are `encode(sha256(cast(<bk> as bytea)),'hex')` cast to `char(64)`. `load_datetime` is `run_started_at`; `record_source` is a short literal (e.g. `'lab'`).
- **DCL contracts are enforced**: 59 DCL models declare `contract: { enforced: true }` with typed columns and PK constraints in `models/dcl/*_schema.yml`. Changing a model's output columns means updating its contract in the same change.
- PostgreSQL indexing is explicit in model configs (btree widely; GIN on the S3-object satellites). Preserve index configs when editing those models.
- `dbt_utils` is the only package (`packages.yml`).
- **No dbt data tests exist** (`tests/` is `.gitkeep` only). `make test` runs `dbt deps && dbt test`, which currently exercises contract/constraint checks, not custom data tests.

### The Redshift rebuild lives elsewhere
The sibling `umccr/orcavault` repo is the **dbt-redshift** rebuild (dbt-core 1.11.12, dbt-redshift 1.10.2, IAM auth, port 5439). It has its own CDC-ephemeral → psa → dcl → mart structure and is NOT the project in this repo. Don't conflate the two: this repo's `orcavault/` is PostgreSQL.

## Mart GraphQL API — `infra/api/lambda-server/`

- **PostGraphile v5** (`postgraphile 5.1.0`) on **Node.js 22 / arm64 Lambda**, fronted by **Fastify 5** via `@fastify/aws-lambda`, served by grafserv.
- Package manager is **pnpm, pinned to `pnpm@11.13.1`** (via `packageManager` in `package.json`). Note this differs from the UI repo (pnpm 10) — use the pinned version here.
- TypeScript (target ES2020, module Node16, strict), bundled with **esbuild** into `dist/index.zip`.
- Preset: Amber + ConnectionFilter + V4 preset, `ignoreRBAC: true`, `disableDefaultMutations: true`, subscriptions off. Only the `mart` schema (`SCHEMA_NAME`) is exposed, read-only.
- Build: `pnpm install && pnpm build`. Local dev: `pnpm start` (port 5000) with `DATABASE_URL` + `SCHEMA_NAME=mart`.
- The `test` script is a placeholder — no API tests exist.
- The API Lambda reads DB credentials at runtime from the AWS Parameters & Secrets Lambda extension (secret `orcahouse/dbuser_ro`), not from env vars.

## Ingest Lambdas — `infra/service-event-ingestion/`

- **Python 3.13**, deployed via `terraform-aws-modules/lambda/aws`, in-VPC, with a locally-built `psycopg2` layer and a `psutil`-free DLQ-backed design.
- Each pipe maps one OrcaBus EventBridge source/detail-type to one `psa.event__*` table. Handlers are idempotent (either `WHERE NOT EXISTS` / `ON CONFLICT`, keyed on `event_id` or a natural key).
- The PSA table DDL is NOT applied by Terraform — after `terraform apply`, run the PSA DDL from `dev/src/psa.sql` against the target DB manually. `dev/src/psa.sql` is the source of truth for these tables.
- Unit tests exist for the VM handler (`pytest`, mocked) but are **not run in CI**.

## Legacy Glue ETL — `infra/glue/` (deprecated → OrcaGlue)

- **AWS Glue 5.0**, `glueetl`, `G.1X`, Python 3; extract with gspread/polars, load into `tsa.*` via Spark JDBC truncate + `aws_s3.table_import_from_s3`.
- The local dev container is Glue 4.0 (`glue_libs_4.0.0_image_01`), which does not match the deployed 5.0 runtime — a known mismatch.
- New TSA sourcing goes to the sibling `umccr/OrcaGlue` (Pulumi + Glue), not here.

## Secrets, SSM, credentials

- Never hard-code secrets. Runtime credentials come from **Secrets Manager** (`orcahouse/dbuser_ro`, `orcahouse/orcavault/{athena,psa_rw,tsa_rw}`, `orcahouse/dms/orcabus-db`) and **SSM Parameter Store** (`/orcahouse/*`, `/umccr/google/drive/*`, Cognito/cert/hosted-zone params).
- Some SSM parameters (the `*_username` ones) are created manually in the console, then referenced by Terraform — not managed by Terraform.
- Aurora and Redshift use provider-managed master/admin passwords (`manage_master_user_password` / `manage_admin_password`).
- Local-dev default credentials (in `dev/compose.yml`, `dev/src/init.sql`, API `local.ts`) are intentionally in-repo and allowlisted with `# pragma: allowlist secret`. Keep that pragma; don't "clean them up."

## Access & operations

- No public database endpoints. Reach `orcahouse-db` or Redshift through the bastions (`infra/ec2/umccr-mgmt`, `infra/ec2/warehouse-mgmt`) via SSM port-forwarding or EC2 Instance Connect Endpoint tunnels.
- Human access is IAM Identity Center SSO roles (`AWSAdministratorAccess`, `PlatformOwnerAccess`, `AWSPowerUserAccess`, `ProdOperator`, `ProdDataExplorer`). Deploying needs an admin session (`iam:PassRole`); non-admins ask for a deploy.
- Daily schedule (UTC, as coded): 13:10 Glue TSA jobs → 13:40 ECS dbt run → 15:00 CDC crawlers → 18:00 mart crawlers; Sundays 17:00 AWS Backup of `orcahouse-db`. Schedule comments in code assume AEDT; they're off by an hour under AEST.

## Repo-wide tooling & commands

Root `Makefile`:
- `make install` — install pre-commit hooks (+ autoupdate).
- `make check` — run pre-commit on all files.
- `make scan` / `make deep` — secret scanning (trufflehog `--only-verified`; `deep` adds ggshield).
- `make baseline` — regenerate the detect-secrets baseline.
- `make test` — `cd orcavault && dbt deps && dbt test`.
- `make test-iac` — CI-only Terraform `fmt -check`/`validate`/`test` for the two EC2 mgmt stacks.

Per-area commands:
- **Terraform**: `terraform init/plan/apply` (+ `workspace select <env>` for UMCCR-era stacks).
- **dbt**: `dbt debug/clean/deps/build/seed/run/test` (from `orcavault/`); `make doc` for docs.
- **Local Postgres**: in `dev/`, `make reload` (full rebuild), `make up/down/psql`, `make sync` (needs `AWS_PROFILE=umccr-dev-admin`).
- **API**: `pnpm install && pnpm build` (in `infra/api/lambda-server/`).
- **ECS dbt image**: `make build|plan|apply|invoke|logs` (in `infra/ecs/orcavault-dbt/`).

## Code style & safety

- **pre-commit enforces**: no commits to `main`/`master`/`release/*`, no AWS credentials or private keys, JSON/YAML validity, and detect-secrets against `.secrets.baseline`.
- Do not commit directly to `main` — use a branch and a PR. The PR build (`.github/workflows/prbuild.yml`) runs pre-commit, trufflehog, `make test` (dbt), and `make test-iac`.
- Keep the detect-secrets baseline current; if a scan flags a new allowlisted local-dev credential, add the `# pragma: allowlist secret` pragma rather than removing the value.
- Match the version policy of each sub-project: don't bump pinned versions (API pnpm/postgraphile, dbt provider versions) casually. Where versions are deliberately unpinned, leave them unless the task is specifically to pin them.
