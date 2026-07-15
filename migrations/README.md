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

### Recommended flags

Always run with `-X` (skip `~/.psqlrc`, so a local psql customization can't
silently change how a migration applies) and `-v ON_ERROR_STOP=1` (a
mid-file statement failure aborts instead of continuing past it):

```bash
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f migrations/<file>.sql
```

Some migration files (any using `pg_index`/`pg_class` catalog lookups
combined with psql's `\gset`/`\if`, e.g.
`2026-07-16-search-vector-hnsw-dedupe.sql`) also read psql variables passed
with `-v`. Check the file's header comment for supported variables before
applying.

### Schema targeting

When applying to a non-default schema (e.g. staging's `PG_SCHEMA=staging`),
set the schema via `PGOPTIONS`, not by editing the SQL file:

```bash
PGOPTIONS="-c search_path=$PG_SCHEMA" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f migrations/<file>.sql
```

Migrations added after 2026-07-16 assert `current_schema()` resolves to a
real schema before making any change, so applying without a `search_path`
that puts the intended schema first fails fast with a clear error instead
of silently landing in the wrong schema (or in `public` by accident).

### `CREATE`/`DROP INDEX CONCURRENTLY`

Files that use `CONCURRENTLY` (search for it in the file before applying)
must run outside any wrapping transaction — do not put `\set AUTOCOMMIT
off` in `~/.psqlrc`, wrap the `psql -f` call in `BEGIN`/`COMMIT`, or paste
the file's contents into a client that batches statements into one
transaction. Applying the file directly with the command above is safe;
these files are written assuming psql's default autocommit-per-statement
behavior.

## Example: the raw_tdx reconciliation migration

`2026-07-04-raw-tdx-schema.sql` provisions the shared `raw_tdx` landing schema used by the two-stage ingestion flow (ADR-0005): the ingestor lands verbatim TDX payloads there at 03:00, and every environment's loader transforms them into its own `PG_SCHEMA` at 03:30. It is the current template for a new dated migration.

Write conventions for ingestion SQL are documented in `docs/storage.md`.
