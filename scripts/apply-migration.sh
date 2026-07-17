#!/usr/bin/env bash
# apply-migration.sh
#
# Operator tool. Applies exactly one migrations/*.sql file to
# $DATABASE_URL with psql, then records it in the schema_migrations ledger
# (ON CONFLICT DO NOTHING, so re-applying an already-recorded file relies on
# the file's own SQL idempotence).
#
# Agents do not run this script — agents cannot reach.
# This is for the operator applying migrations by hand.
#
# Usage:
#   DATABASE_URL=... scripts/apply-migration.sh migrations/<file>.sql
#
# For staging, set PGOPTIONS to target the staging schema first, same as
# every other operator command against:
#   PGOPTIONS="-c search_path=staging" DATABASE_URL=... \
#       scripts/apply-migration.sh migrations/<file>.sql
#
# A migration file that itself requires -v target_schema=... (see
# migrations/README.md "Schema targeting") needs that flag passed through
# separately with plain psql; this wrapper does not guess target_schema for
# you, since guessing it wrong is exactly the failure mode those files guard
# against. Set TARGET_SCHEMA=staging|public to forward it automatically:
#   PGOPTIONS="-c search_path=staging" TARGET_SCHEMA=staging DATABASE_URL=... \
#       scripts/apply-migration.sh migrations/<file>.sql
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: DATABASE_URL=... $0 migrations/<file>.sql" >&2
    exit 2
fi

file="$1"
if [ ! -f "$file" ]; then
    echo "apply-migration: $file does not exist" >&2
    exit 2
fi

: "${DATABASE_URL:?DATABASE_URL is required}"

name="$(basename "$file")"
checksum="$(sha256sum "$file" | awk '{print $1}')"
applied_by="${APPLIED_BY:-${USER:-unknown}}"

psql_args=(-X -v ON_ERROR_STOP=1)
if [ -n "${TARGET_SCHEMA:-}" ]; then
    psql_args+=(-v "target_schema=${TARGET_SCHEMA}")
fi

echo "== applying $name =="
psql "$DATABASE_URL" "${psql_args[@]}" -f "$file"

echo "== recording $name in schema_migrations =="
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -v "name=${name}" -v "checksum=${checksum}" -v "by=${applied_by}" \
    -c "INSERT INTO schema_migrations (filename, sha256, applied_by) VALUES (:'name', :'checksum', :'by')
        ON CONFLICT (filename) DO NOTHING;"

echo "apply-migration: $name applied and recorded."
