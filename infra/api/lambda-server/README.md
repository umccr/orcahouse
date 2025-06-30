# PostGraphile Lambda Server

This project provides a serverless GraphQL API using [PostGraphile v5](https://www.graphile.org/postgraphile/) and Fastify, designed to run on AWS Lambda. It introspects a PostgreSQL schema and auto-generates a GraphQL endpoint.

## Scripts
<!-- pragma: allowlist nextline secret -->
- `pnpm start` — Start the server locally. If `DATABASE_URL` is not set, it defaults to `postgres://orcabus:orcabus@localhost:5432/metadata_manager`. 
- `pnpm build` — Bundles the Lambda asset into the `dist/` directory.

## Local Development

1. Ensure you have a local PostgreSQL instance running.
2. Install dependencies and run:

```sh
pnpm install
pnpm start
```
