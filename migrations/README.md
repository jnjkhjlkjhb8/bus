# Database Migrations

SQL migrations in this directory are the single source of truth for schema changes and are **hand-applied** — there is no migration runner. The user applies each file to Azure with `psql`; agents cannot reach the database directly.

## Naming

New DDL is a new dated file: `YYYY-MM-DD-short-name.sql` (e.g. `2026-07-04-raw-tdx-schema.sql`). Older files use a legacy `NNNN_name.sql` numeric prefix; do not add new files in that style.

Do not edit a migration after it has been applied to staging or production; create the next dated file instead.

## Apply

```bash
psql "$DATABASE_URL" -f migrations/<file>.sql
```

For staging, `DATABASE_URL` points at the Azure instance with `PG_SCHEMA=staging`; for prod it targets the `public` schema (see `AGENTS.md`).

## Example: the raw_tdx reconciliation migration

`2026-07-04-raw-tdx-schema.sql` provisions the shared `raw_tdx` landing schema used by the two-stage ingestion flow (ADR-0005): the ingestor lands verbatim TDX payloads there at 03:00, and every environment's loader transforms them into its own `PG_SCHEMA` at 03:30. It is the current template for a new dated migration.

Write conventions for ingestion SQL are documented in `docs/storage.md`.
