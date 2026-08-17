#!/usr/bin/env bash
# render-env.sh
#
# every service's env_file at the same single ENV_FILE, so a container
# compromise anywhere (router, functions, ingestor, loader, powersync) leaked
# every credential in that env file (DB, TDX, MQTT, PowerSync, Sentry,
# Firebase) regardless of whether that service ever reads it.
#
# This script keeps the operator-facing contract unchanged — one env/<env>.env
# file, filled in exactly as before — and produces six per-service env files
# from it, each containing only the KEY=value lines that service's allowlist
# (scripts/env-allowlists/<service>.txt) names. docker-compose.yaml's
# env_file: directives were repointed at the rendered files (ENV_FILE_ROUTER,
# ENV_FILE_FUNCTIONS, ENV_FILE_INGESTOR, ENV_FILE_LOADER, ENV_FILE_POWERSYNC,
# ENV_FILE_MOTIS),
# each defaulting back to ${ENV_FILE:-./.env} when unset, so a bare
# `docker compose up` (or check-compose-isolation.sh / check-container-
# hardening.sh, which only ever set ENV_FILE) keeps working unchanged.
#
# This was chosen over splitting env/<env>.env itself into six
# operator-maintained files: same security property (each container only
# ever sees its own allowlisted vars), but a strictly smaller diff and zero
# migration cost for the operator, who keeps editing the one file per env
# they already know. See docs/config.md for the full rationale.
#
# Usage: scripts/render-env.sh <source-env-file> <output-dir>
#   Writes <output-dir>/{router,functions,ingestor,loader,powersync,motis}.env.
#   A KEY in the source file with no line in any allowlist is silently
#   dropped from every rendered file (by design — see scripts/env-
#   allowlists/README.md-style comments in each allowlist file for why a var
#   is absent). Comments/blank lines in the source file are ignored; only
#   KEY=value lines matching an allowlisted name are copied, verbatim
#   (including any inline value containing '=').
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
allowlist_dir="$repo_root/scripts/env-allowlists"
services=(router functions ingestor loader powersync motis)

usage() {
  echo "usage: $(basename "$0") <source-env-file> <output-dir>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
source_file="$1"
out_dir="$2"

[ -f "$source_file" ] || { echo "render-env.sh: source env file not found: $source_file" >&2; exit 1; }

mkdir -p "$out_dir"

for service in "${services[@]}"; do
  allowlist="$allowlist_dir/${service}.txt"
  [ -f "$allowlist" ] || { echo "render-env.sh: missing allowlist $allowlist" >&2; exit 1; }
  out_file="$out_dir/${service}.env"
  : >"$out_file"
  while IFS= read -r key; do
    # Skip blank lines and #-comments in the allowlist file itself.
    case "$key" in
      ''|'#'*) continue ;;
    esac
    # Exact-name match against KEY=... lines in the source file (anchored on
    # both ends of the key so ROUTER_DB_MAX_CONNS never matches as a prefix
    # of some other ROUTER_DB_MAX_CONNS_FOO). Only the first match wins,
    # mirroring shell/dotenv semantics for a file with (accidentally)
    # duplicated keys.
    line=$(grep -m1 -E "^${key}=" "$source_file" || true)
    if [ -n "$line" ]; then
      printf '%s\n' "$line" >>"$out_file"
    fi
  done <"$allowlist"
done

echo "render-env.sh: wrote ${services[*]/%/.env} to $out_dir (source: $source_file)"
