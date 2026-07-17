#!/usr/bin/env bash
# check-env-allowlist.sh
#
# tracked example env file through scripts/render-env.sh and asserts every
# resulting per-service env file contains only KEY=value lines whose KEY is
# listed in that service's scripts/env-allowlists/<service>.txt. This is what
# actually catches a mis-scoped allowlist edit (a var added to the wrong
# service's allowlist file) or a render-env.sh regression that stops
# filtering — render-env.sh itself only ever emits an allowlisted subset by
# construction, so this check re-derives "subset" independently by reading
# both the rendered file and the allowlist file and diffing their key sets,
# rather than trusting the renderer's own logic.
#
# TDX_CLIENT_ID/TDX_CLIENT_SECRET intentionally appear in router's and
# functions' allowlists, not just ingestor's — see the comment atop
# scripts/env-allowlists/router.txt (MaaS carve-out) and functions.txt
# (registerLiveCrons realtime fetches) for why, and docs/config.md for the
# full per-service table.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

allowlist_dir="scripts/env-allowlists"
services=(router functions ingestor loader powersync)
envs=(test staging prod)

fail=0
note() { printf '%s\n' "$*"; }
ok() { printf '  OK   %s\n' "$*"; }
bad() {
  printf '  FAIL %s\n' "$*"
  fail=1
}

allowlist_keys() {
  # scripts/env-allowlists/<service>.txt -> sorted, deduped var names,
  # skipping blank lines and #-comments.
  grep -vE '^\s*(#|$)' "$allowlist_dir/${1}.txt" | sort -u
}

rendered_keys() {
  # <rendered-file> -> sorted, deduped KEY names from KEY=value lines.
  [ -f "$1" ] || return 0
  cut -d= -f1 "$1" | sort -u
}

check_env() {
  local env_name="$1" source_file="env/${env_name}.env.example"
  local work_dir
  work_dir="$(mktemp -d)"
  ./scripts/render-env.sh "$source_file" "$work_dir" >/dev/null
  for service in "${services[@]}"; do
    local rendered="$work_dir/${service}.env"
    local extra
    extra=$(comm -23 <(rendered_keys "$rendered") <(allowlist_keys "$service") || true)
    if [ -n "$extra" ]; then
      bad "$env_name/$service: rendered env has keys outside its allowlist: $(echo "$extra" | tr '\n' ' ')"
    else
      ok "$env_name/$service: rendered env ⊆ allowlist ($(rendered_keys "$rendered" | wc -l | tr -d ' ') keys)"
    fi
  done
  rm -rf "$work_dir"
}

note "== Per-service env allowlist (render + subset check, all example envs) =="
for env_name in "${envs[@]}"; do
  check_env "$env_name"
done

if [ "$fail" -ne 0 ]; then
  note ""
  note "RESULT: RED — see FAIL lines above."
  exit 1
fi

note ""
note "RESULT: GREEN — every service's rendered env is a subset of its allowlist."
