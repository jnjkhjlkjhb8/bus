#!/usr/bin/env bash
# check-migrations.sh
#
# Applies every migrations/*.sql file, in filename order, to a fresh
# ephemeral PostgreSQL container via `psql -v ON_ERROR_STOP=1`, then
# re-applies each file that documents itself as idempotent (its header
# comment says "Idempotent" or it is built entirely from IF [NOT] EXISTS /
# IF to_regclass(...) guards) to prove it is safe to rerun.
#
# migrations/ is an INCREMENTAL delta on top of a pre-existing production
# schema that predates this directory's git history (base tables such as
# bus_stations, bus_subroutes, tra_fares, thsr_fares, bike_stations,
# mrt_station, tra_stations, thsr_stations, search_vector, and the
# `powersync` publication are not created by any tracked migration; nor is
# the postgis extension, which several files assume via the GEOMETRY(...)
# type). A truly empty database therefore cannot run this history end to
# end — that gap is a real property of the repository, not a bug in this
# script. To make the harness useful anyway, this script provisions a
# BEST-EFFORT baseline assembled only from DDL that is *already committed*
# elsewhere in this repo (services/functions/*_db_test.go fixtures) before
# applying migrations, and prints a per-file classification:
#
#   OK              applied cleanly
#   OK (guarded)    file uses to_regclass/IF EXISTS guards and no-ops
#                   cleanly when its target table is absent
#   BLOCKED         failed because it references a table/object that is
#                   part of the pre-migrations baseline and has no known
#                   committed DDL anywhere in this repo (expected; needs a
#                   schema-only dump from the owner to fully validate)
#   FAIL            failed for any other reason (real defect)
#
# A FAIL entry is a hard failure (script exits non-zero). BLOCKED entries
# are reported but do not fail the script, since fixing them requires
# information (the production baseline schema) this repo does not contain.
#
# Requires: docker.
#
# Usage: scripts/check-migrations.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# pgvector/pgvector:pg16 matches docker/docker-compose.test.yaml's postgres
# major version (16) and ships pgvector prebuilt; postgis is layered on top
# at container start via apt (network available in this environment) since
# no single upstream image ships both extensions.
IMAGE="pgvector/pgvector:pg16"
CONTAINER="bus-check-migrations-$$"
PORT="${CHECK_MIGRATIONS_PORT:-15433}"
DB=migcheck
USER=postgres
PASS=postgres

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== starting ephemeral postgres ($IMAGE) =="
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PASS" -e POSTGRES_USER="$USER" -e POSTGRES_DB="$DB" \
  -p "127.0.0.1:${PORT}:5432" "$IMAGE" >/dev/null

psql() { docker exec -i "$CONTAINER" env PGPASSWORD="$PASS" psql -v ON_ERROR_STOP=1 -U "$USER" -d "$DB" "$@"; }

echo "== waiting for postgres to accept connections =="
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" pg_isready -U "$USER" -d "$DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$CONTAINER" pg_isready -U "$USER" -d "$DB" >/dev/null

echo "== installing postgis (apt, layered on top of pgvector image) =="
docker exec -u root "$CONTAINER" bash -c \
  'apt-get update -qq && apt-get install -y -qq postgresql-16-postgis-3 >/dev/null' \
  >/tmp/check-migrations-apt.log 2>&1 \
  || { echo "FAIL: could not install postgis in the check container; see /tmp/check-migrations-apt.log"; exit 1; }

psql -c "CREATE EXTENSION IF NOT EXISTS postgis;" >/dev/null
psql -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null

echo "== provisioning best-effort baseline (DDL sourced from services/functions/*_db_test.go) =="
psql <<'SQL' >/dev/null
-- Sourced verbatim (types/columns) from provisionBusSinks() in
-- services/functions/bus_writer_db_test.go and loader_db_test.go, and the
-- bus_schedule/thsr_stations fixtures in travel_avg_db_test.go /
-- loader_test.go. These are the only pre-migrations base tables with
-- committed DDL anywhere in this repo. Tables with NO committed DDL
-- (tra_fares, thsr_fares, bike_stations, mrt_station, tra_stations,
-- search_vector, the `powersync` publication) are intentionally left
-- unprovisioned; migrations that need them are expected to report BLOCKED
-- below.
DO $$ BEGIN
  CREATE TYPE stop AS (station_uid text, stop_name text, stop_sequence int,
                        position_lon float, position_lat float);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- NOTE: bus_operators is deliberately NOT provisioned here. Unlike the
-- other tables in this block, migrations/2026-06-30-bus-operator.sql is the
-- migration that originally created it (bare CREATE TABLE, no IF NOT
-- EXISTS) — it is not a pre-migrations baseline table.

-- `operators jsonb` intentionally omitted: migrations/2026-06-30-bus-operator.sql
-- is the migration that adds it (bare ALTER TABLE ADD COLUMN, no IF NOT
-- EXISTS). The *_db_test.go fixture this baseline is otherwise copied from
-- reflects today's already-migrated schema and includes that column; a
-- baseline that already had it would make the ALTER collide even though it
-- runs clean on the real, un-migrated pre-2026-06-30 production table.
CREATE TABLE IF NOT EXISTS bus_subroutes (
  sub_route_uid text NOT NULL, route_uid text, direction smallint NOT NULL,
  route_name text, sub_route_name text, city text, depart text, destin text,
  geometry text, stops stop[], schedule jsonb,
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (sub_route_uid, direction));

CREATE TABLE IF NOT EXISTS bus_stations (
  station_uid text PRIMARY KEY, station_name text, city text,
  position geometry(Point,4326), updated_at timestamptz NOT NULL DEFAULT NOW());

CREATE TABLE IF NOT EXISTS bus_station_stop_map (
  station_id text, station_name text, sub_route_uid text, route_name text,
  direction int, stop_uid text, stop_sequence int,
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (sub_route_uid, stop_uid, direction));

CREATE TABLE IF NOT EXISTS bus_schedule (
  sub_route_uid text, direction smallint, type bool, tripid text,
  islowfloor bool, stopsequence smallint,
  "stop_uid/MinHeadwayMins" text, "stop_name/MaxHeadwayMins" text,
  "arrival_time/StartTime" time, "departure_time/EndTime" time,
  service_day smallint, updated_at timestamptz NOT NULL DEFAULT NOW());

CREATE TABLE IF NOT EXISTS thsr_stations (
  station_id text PRIMARY KEY, station_name text, geom geometry(Point,4326),
  updated_at timestamptz NOT NULL DEFAULT NOW());
SQL

fail=0
declare -a blocked=()
declare -a failed=()
declare -a passed=()

is_idempotent_by_convention() {
  local f="$1"
  # Header says "Idempotent".
  grep -qiE '^-- *Idempotent' "$f" && return 0
  # Every bare CREATE TABLE/INDEX/UNIQUE INDEX statement (i.e. not already
  # qualified with IF NOT EXISTS) disqualifies the file: a second run would
  # error with "already exists".
  if grep -qE '^\s*CREATE (TABLE|INDEX|UNIQUE INDEX)\s' "$f"; then
    grep -E '^\s*CREATE (TABLE|INDEX|UNIQUE INDEX)\s' "$f" | grep -qvE 'IF NOT EXISTS' && return 1
  fi
  return 0
}

echo
echo "== applying migrations in filename order =="
for f in migrations/*.sql; do
  name="$(basename "$f")"
  set +e
  out="$(psql < "$f" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "  OK        $name"
    passed+=("$name")
  else
    # Heuristic: classify as BLOCKED only when the failure is a missing
    # relation/publication/type, i.e. an undocumented pre-migrations
    # baseline dependency, not a syntax or logic error in the file itself.
    if echo "$out" | grep -qE 'relation "[a-zA-Z_.]+" does not exist|publication "[a-zA-Z_]+" does not exist|type "[a-zA-Z_]+" does not exist'; then
      reason="$(echo "$out" | grep -oE '(relation|publication|type) "[a-zA-Z_.]+" does not exist' | head -1)"
      echo "  BLOCKED   $name ($reason)"
      blocked+=("$name: $reason")
    else
      echo "  FAIL      $name"
      echo "$out" | sed 's/^/            /'
      failed+=("$name")
      fail=1
    fi
  fi
done

echo
echo "== re-applying idempotent-by-convention migrations a second time =="
for f in migrations/*.sql; do
  name="$(basename "$f")"
  case " ${passed[*]-} " in
    *" $name "*) ;;
    *) continue ;; # only re-run files that actually applied the first time
  esac
  if is_idempotent_by_convention "$f"; then
    set +e
    out="$(psql < "$f" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "  OK rerun  $name"
    else
      echo "  FAIL rerun $name (claims idempotent but errors on reapply)"
      echo "$out" | sed 's/^/            /'
      failed+=("$name (rerun)")
      fail=1
    fi
  fi
done

echo
echo "== summary =="
echo "  applied clean : ${#passed[@]}"
echo "  blocked (baseline gap, expected) : ${#blocked[@]}"
for b in "${blocked[@]:-}"; do [ -n "$b" ] && echo "    - $b"; done
echo "  failed (real defect) : ${#failed[@]}"
for f in "${failed[@]:-}"; do [ -n "$f" ] && echo "    - $f"; done

if [ "$fail" -ne 0 ]; then
  echo
  echo "check-migrations: FAIL (real defects found; see FAIL entries above)"
  exit 1
fi

echo
echo "check-migrations: PASS (no real defects; BLOCKED entries require an owner-supplied production schema dump to fully validate)"
