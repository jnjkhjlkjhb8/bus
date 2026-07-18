#!/usr/bin/env bash
# deploy-transaction.sh <staging|prod> <router-image-ref> <functions-image-ref>
#
# Runs on the deploy host (invoked over SSH by .github/workflows/
# deploy-staging.yaml and deploy-prod.yaml, never on the GitHub runner).
# Promotes the exact CI-built digests build-images.yaml published for one
# commit -- it never builds an image itself. ROUTER_IMAGE/FUNCTIONS_IMAGE
# override the `image:` keys docker/docker-compose.yaml declares for
# router/functions/ingestor/loader (ingestor and loader share the functions
# image, differentiated only by ROLE), so `docker compose pull` fetches the
# named registry digest instead of anything the tracked `build:` block would
# produce -- `docker compose pull` disregards `build:` and always pulls
# `image:` when both are present.
#
# Transaction: verify the migration ledger (every dated migrations/*.sql
# recorded in this environment's schema_migrations with a matching checksum
# -- never applies SQL itself; migrations stay hand-applied, ADR-0010) ->
# capture the digests currently running (for rollback) -> pull
# the new digests -> up --wait (blocks on every service's healthcheck,
# docker/docker-compose.yaml) -> smoke-test the router -> on any failure,
# revert to the captured digests and exit 1. A successful run records its
# own digests as the new last-known-good for the next deploy's rollback
# target.
set -euo pipefail

env_name="${1:?usage: deploy-transaction.sh <staging|prod> <router-image-ref> <functions-image-ref>}"
router_image="${2:?usage: deploy-transaction.sh <staging|prod> <router-image-ref> <functions-image-ref>}"
functions_image="${3:?usage: deploy-transaction.sh <staging|prod> <router-image-ref> <functions-image-ref>}"

case "$env_name" in
  staging)
    project=staging
    env_file=env/staging.env
    overlay=docker/docker-compose.staging.yaml
    ;;
  prod)
    project=prod
    env_file=env/prod.env
    overlay=docker/docker-compose.prod.yaml
    ;;
  *)
    echo "deploy-transaction: unknown environment '$env_name' (want staging or prod)" >&2
    exit 1
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

state_dir="/var/lib/bus"
state_file="$state_dir/last-known-good-${env_name}.json"

log() { printf '[deploy-transaction] %s\n' "$*"; }

# Per-service env allowlist (O7 / review_results.md P1-15): render the five
# per-service env files from the operator's single env/<env>.env before any
# compose call, exactly as Makefile's render-env-% targets do for
# `make up-staging`/`make up-prod`. Without this, every container on a real
# deploy would fall back to the full ${ENV_FILE} and see every credential --
# silently defeating the allowlist on the one path that runs in production.
# Fail loudly: a failed render or a missing rendered file aborts the deploy
# before anything is pulled or restarted.
rendered_dir="env/.rendered/${env_name}"
if ! ./scripts/render-env.sh "$env_file" "$rendered_dir"; then
  log "FATAL: scripts/render-env.sh failed for $env_file -- refusing to deploy with un-scoped env files"
  exit 1
fi
for svc in router functions ingestor loader powersync; do
  if [ ! -s "$rendered_dir/${svc}.env" ]; then
    log "FATAL: rendered env file $rendered_dir/${svc}.env is missing or empty -- refusing to deploy with un-scoped env files"
    exit 1
  fi
done
log "rendered per-service env files into $rendered_dir"

# Migration guard: refuse to promote code whose schema prerequisites are not
# in place. Diffs migrations/*.sql against this environment's
# schema_migrations ledger (written only by scripts/apply-migration.sh) and
# blocks on (a) a dated file the ledger has no record of and (b) a checksum
# mismatch (the file was edited after being applied). Files whose first line
# is `-- REPLAY: skip` (superseded or one-shot cleanups, migrations/README.md)
# are exempt from the missing-check but still checksum-verified when
# recorded. The guard only reads; applying migrations remains a manual
# operator step (ADR-0010).
verify_migration_ledger() {
  local db_url pg_schema
  db_url=$(grep -m1 '^DATABASE_URL=' "$env_file" | cut -d= -f2-)
  pg_schema=$(grep -m1 '^PG_SCHEMA=' "$env_file" | cut -d= -f2-)
  if [ -z "$db_url" ] || [ -z "$pg_schema" ]; then
    log "FATAL: DATABASE_URL or PG_SCHEMA missing from $env_file -- cannot verify the migration ledger"
    return 1
  fi

  # Same pinned image ci.yaml uses for its postgres service; the deploy host
  # has no psql of its own.
  local ledger
  if ! ledger=$(docker run --rm \
      -e PGOPTIONS="-c search_path=${pg_schema}" \
      postgres:16-alpine@sha256:57c72fd2a128e416c7fcc499958864df5301e940bca0a56f58fddf30ffc07777 \
      psql "$db_url" -X -v ON_ERROR_STOP=1 -At -F ' ' \
      -c 'SELECT filename, sha256 FROM schema_migrations'); then
    log "FATAL: could not read ${pg_schema}.schema_migrations -- refusing to deploy without a readable migration ledger (if this environment predates the ledger, apply migrations/2026-07-17-schema-migrations-ledger.sql first)"
    return 1
  fi

  local failed=0 f name want have
  for f in migrations/*.sql; do
    name=$(basename "$f")
    want=$(sha256sum "$f" | awk '{print $1}')
    have=$(printf '%s\n' "$ledger" | awk -v n="$name" '$1 == n {print $2}')
    if [ -z "$have" ]; then
      if head -n1 "$f" | grep -q '^-- REPLAY: skip'; then
        continue
      fi
      log "FATAL: $name is not recorded in ${pg_schema}.schema_migrations -- apply it (scripts/apply-migration.sh), or backfill the ledger if it was applied before the ledger existed (migrations/README.md, \"Ledger\")"
      failed=1
    elif [ "$have" != "$want" ]; then
      log "FATAL: $name checksum differs from the recorded apply in ${pg_schema}.schema_migrations -- the file was edited after being applied; supersede it with a new dated file (migrations/README.md, \"Naming\")"
      failed=1
    fi
  done

  if [ "$failed" -ne 0 ]; then
    return 1
  fi
  log "migration ledger OK: every dated migration is recorded in ${pg_schema}.schema_migrations with a matching checksum"
}

if ! verify_migration_ledger; then
  log "deploy REFUSED: migration ledger verification failed -- nothing was pulled or restarted"
  exit 1
fi

# compose <args...> -- one invocation shape shared by every call below, mirroring
# Makefile's COMPOSE_STAGING/COMPOSE_PROD (same project name, env file, per-
# service rendered env files, and overlay list) so this script and
# `make up-staging`/`make up-prod` never target different stacks.
compose() {
  local image_router="$1" image_functions="$2"
  shift 2
  ENV_FILE="$env_file" \
    ENV_FILE_ROUTER="$rendered_dir/router.env" \
    ENV_FILE_FUNCTIONS="$rendered_dir/functions.env" \
    ENV_FILE_INGESTOR="$rendered_dir/ingestor.env" \
    ENV_FILE_LOADER="$rendered_dir/loader.env" \
    ENV_FILE_POWERSYNC="$rendered_dir/powersync.env" \
    ROUTER_IMAGE="$image_router" FUNCTIONS_IMAGE="$image_functions" \
    docker compose --project-directory . -p "$project" --env-file "$env_file" \
    -f docker/docker-compose.yaml -f "$overlay" "$@"
}

# running_image <service> -- the exact image reference (as passed to
# `image:` when the container was created) of the currently running
# container for one service, or empty if none is running. Config.Image
# records the string docker was given to create the container, which for a
# compose service with `image: ${ROUTER_IMAGE:-router}` is exactly the
# digest ref a previous deploy-transaction.sh run supplied -- so this reads
# ground truth from the host instead of trusting a state file that could
# have drifted from a manual `docker compose` invocation.
running_image() {
  local service="$1" cid
  cid=$(compose "$router_image" "$functions_image" ps -q "$service" 2>/dev/null || true)
  [ -z "$cid" ] && return 0
  docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null || true
}

prev_router=$(running_image router)
prev_functions=$(running_image functions)
if [ -n "$prev_router" ] && [ -n "$prev_functions" ]; then
  log "captured currently running images for rollback: router=$prev_router functions=$prev_functions"
else
  log "no currently running router/functions image found (first deploy?) -- rollback unavailable this run"
fi

# router_endpoint -- host_ip:port docker publishes router's HTTP API on,
# read from the actual compose config instead of assuming a fixed port
# (staging remaps ROUTER_HTTP_PORT to avoid colliding with prod on the same
# host; see scripts/check-compose-isolation.sh).
router_endpoint() {
  compose "$router_image" "$functions_image" port router 8080 2>/dev/null || true
}

smoke_test() {
  local endpoint
  endpoint=$(router_endpoint)
  if [ -z "$endpoint" ]; then
    log "smoke test FAILED: could not resolve router's published HTTP port"
    return 1
  fi
  if ! curl -sf --max-time 5 "http://${endpoint}/api/.well-known/jwks.json" >/dev/null; then
    log "smoke test FAILED: GET http://${endpoint}/api/.well-known/jwks.json did not return 200"
    return 1
  fi
  local not_healthy
  not_healthy=$(compose "$router_image" "$functions_image" ps --format json \
    | grep -o '"Health":"[a-z]*"' | grep -v '"Health":"healthy"' || true)
  if [ -n "$not_healthy" ]; then
    log "smoke test FAILED: not every service reports healthy: $not_healthy"
    return 1
  fi
  log "smoke test OK: router jwks endpoint 200, all services healthy"
}

deploy_digests() {
  local router_ref="$1" functions_ref="$2"
  compose "$router_ref" "$functions_ref" pull router functions ingestor loader
  compose "$router_ref" "$functions_ref" up -d --wait --no-build
}

record_last_known_good() {
  mkdir -p "$state_dir"
  cat > "$state_file" <<EOF
{
  "environment": "$env_name",
  "router": "$router_image",
  "functions": "$functions_image",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  log "recorded new last-known-good: $state_file"
}

log "deploying to $env_name: router=$router_image functions=$functions_image"
if deploy_digests "$router_image" "$functions_image" && smoke_test; then
  record_last_known_good
  log "deploy SUCCEEDED"
  exit 0
fi

log "deploy FAILED"
if [ -n "$prev_router" ] && [ -n "$prev_functions" ]; then
  log "rolling back to router=$prev_router functions=$prev_functions"
  if deploy_digests "$prev_router" "$prev_functions"; then
    log "rollback SUCCEEDED -- $env_name is back on the previously running images"
  else
    log "rollback FAILED -- $env_name may be left in a partially-updated state; manual intervention required"
  fi
else
  log "no previous image captured -- nothing to roll back to; manual intervention required"
fi
exit 1
