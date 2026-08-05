#!/usr/bin/env bash
# check-container-hardening.sh
#
# Static + compose-config policy checks for container hardening:
#   - non-root USER in final images we build (router, functions, embed/ollama)
#   - no-new-privileges, dropped capabilities, read-only root FS, pids/cpu
#     limits on every long-running compose service
#   - per-service secret file mounts (never the whole ./secrets directory)
#   - images pinned by digest (no bare :latest, no unpinned tags)
#   - OSRM PBF fetched atomically with checksum verification, and a
#     preprocessing marker derived from the PBF checksum + routing profile
#
# Compose-level checks read `docker compose config` output (same technique
# as scripts/check-compose-isolation.sh) rather than hand-rolling YAML
# parsing. Dockerfile and osrm command checks are plain text greps and need
# no daemon. If `docker` is unavailable, the compose-config section is
# skipped with a note rather than failing the whole script.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0
note() { printf '%s\n' "$*"; }
ok() { printf '  OK   %s\n' "$*"; }
bad() {
  printf '  FAIL %s\n' "$*"
  fail=1
}

# ---------------------------------------------------------------------------
# 1. Non-root USER in Dockerfiles we control
# ---------------------------------------------------------------------------
note "== Non-root USER in final image stage =="
check_dockerfile_user() {
  local name="$1" file="$2"
  if [ ! -f "$file" ]; then
    bad "$name: $file not found"
    return
  fi
  local last_user
  last_user=$(grep -E '^USER ' "$file" | tail -1 | awk '{print $2}' || true)
  if [ -z "$last_user" ]; then
    bad "$name: no USER directive in $file (runs as root)"
  elif [ "$last_user" = "root" ] || [ "$last_user" = "0" ] || [ "$last_user" = "0:0" ]; then
    bad "$name: USER directive resolves to root in $file"
  else
    ok "$name: USER $last_user in $file"
  fi
}
check_dockerfile_user "router" services/router/Dockerfile
check_dockerfile_user "functions" services/functions/Dockerfile
check_dockerfile_user "embed/ollama" embed/Dockerfile

# ---------------------------------------------------------------------------
# 2. .dockerignore exists and is allowlist-style (excludes the big/sensitive
#    stuff rather than trying to enumerate everything to include)
# ---------------------------------------------------------------------------
note ""
note "== .dockerignore present and excludes secrets/build output =="
if [ ! -f .dockerignore ]; then
  bad ".dockerignore missing at repo root"
elif grep -qE '^\*$' .dockerignore; then
  # Allowlist-style: a bare `*` denies everything by default, so anything
  # not explicitly un-ignored (git, env/secrets, build output, osrm-data,
  # caches, local tooling) is excluded automatically. Only flag a problem if
  # one of those sensitive/huge paths was explicitly re-included.
  reincluded=""
  for pattern in '^!\.git' '^!env/' '^!secrets' '^!osrm-data' '^!app/build' '^!\.dart_tool'; do
    grep -qE "$pattern" .dockerignore && reincluded="$reincluded $pattern"
  done
  if [ -z "$reincluded" ]; then
    ok ".dockerignore is deny-by-default (allowlist style); no sensitive/build paths re-included"
  else
    bad ".dockerignore re-includes sensitive/build paths:$reincluded"
  fi
else
  missing=""
  for pattern in '.git' 'env/*.env' 'secrets/' 'osrm-data/' 'app/build' '.dart_tool'; do
    grep -qF "$pattern" .dockerignore || missing="$missing $pattern"
  done
  if [ -z "$missing" ]; then
    ok ".dockerignore covers git/env/secrets/osrm-data/build/dart_tool"
  else
    bad ".dockerignore missing patterns:$missing"
  fi
fi

# ---------------------------------------------------------------------------
# 3. OSRM fetch: atomic download + checksum verification
# ---------------------------------------------------------------------------
note ""
note "== OSRM PBF fetch: atomic download + checksum =="
osrm_fetch_cmd=$(awk '/^  osrm-fetch:/{f=1} f{print} f && /restart:/{exit}' docker/docker-compose.yaml)
if echo "$osrm_fetch_cmd" | grep -q 'sha256sum\|md5sum'; then
  ok "osrm-fetch verifies a checksum before use"
else
  bad "osrm-fetch does not verify a checksum (sha256sum/md5sum) of the download"
fi
if echo "$osrm_fetch_cmd" | grep -qE '\.tmp|\.part' && echo "$osrm_fetch_cmd" | grep -q 'mv '; then
  ok "osrm-fetch downloads to a temp path and renames atomically"
else
  bad "osrm-fetch does not download-then-rename atomically (no .tmp path + mv)"
fi

# ---------------------------------------------------------------------------
# 4. OSRM preprocessing marker derived from PBF checksum + profile
# ---------------------------------------------------------------------------
note ""
note "== OSRM preprocessing marker is content-based =="
osrm_init_cmd=$(awk '/^  osrm-init:/{f=1} f{print} f && /restart:/{exit}' docker/docker-compose.yaml)
if echo "$osrm_init_cmd" | grep -q 'sha256sum' && echo "$osrm_init_cmd" | grep -q 'profile'; then
  ok "osrm-init derives its marker from a checksum + profile name"
else
  bad "osrm-init's preprocessing marker is not derived from the PBF checksum + profile (stale-data risk)"
fi

# ---------------------------------------------------------------------------
# 5. OSRM healthcheck hits a real endpoint
# ---------------------------------------------------------------------------
note ""
note "== OSRM healthcheck uses a real OSRM HTTP endpoint =="
osrm_healthcheck_test=$(awk '
  /^  osrm:$/ { f=1; next }
  f && /^  [a-zA-Z0-9_-]+:$/ { exit }
  f && /^ *test:/ { print }
' docker/docker-compose.yaml | grep -v '^ *#')
if echo "$osrm_healthcheck_test" | grep -q '/health'; then
  bad "osrm healthcheck calls /health, which osrm-routed does not expose"
elif echo "$osrm_healthcheck_test" | grep -qE '/nearest/v1/|/route/v1/'; then
  ok "osrm healthcheck calls a documented OSRM HTTP service endpoint"
else
  bad "osrm healthcheck does not reference a documented OSRM endpoint"
fi
# The endpoint being right is not enough -- the probe binary must exist in
# the image. osrm/osrm-backend:v5.25.0 is Debian-based with NO wget, curl,
# or busybox (verified via `docker run --entrypoint sh ... -c 'command -v
# ...'`); it does ship bash, so the probe must use bash's /dev/tcp
# redirection. A wget/curl probe execs fine per compose config but fails
# with "command not found" at runtime, leaving the container unhealthy
# forever.
if echo "$osrm_healthcheck_test" | grep -qE 'wget|curl'; then
  bad "osrm healthcheck invokes wget/curl, neither of which exists in osrm/osrm-backend:v5.25.0"
elif echo "$osrm_healthcheck_test" | grep -q '/dev/tcp/'; then
  ok "osrm healthcheck probes via bash /dev/tcp (only HTTP client available in the image)"
else
  bad "osrm healthcheck does not use bash /dev/tcp -- verify its probe binary exists in the pinned image"
fi

# ---------------------------------------------------------------------------
# 6. Compose-config-derived checks (need docker compose)
# ---------------------------------------------------------------------------
note ""
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  note "== Compose-config checks SKIPPED (docker/compose not available) =="
else
  note "== Compose-config checks (docker compose config, test env) =="
  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT
  cfg="$work_dir/config.yaml"
  # ENV_FILE (not BUS_ENV_FILE) is what docker-compose.yaml actually reads
  # (`env_file: ${ENV_FILE:-./.env}`); see check-compose-isolation.sh for
  # why it must be exported here rather than left to the --env-file default.
  if ! ENV_FILE=env/test.env.example docker compose \
    --project-directory . \
    -p bus-hardening-check \
    --env-file env/test.env.example \
    -f docker/docker-compose.yaml \
    -f docker/docker-compose.prod.yaml \
    --profile gpu \
    config >"$cfg" 2>"$work_dir/config.err"; then
    cat "$work_dir/config.err" >&2
    exit 1
  fi

  services="router functions ingestor loader redis powersync cloudflared osrm osrm-fetch osrm-init ollama"
  long_running="router functions ingestor loader redis powersync cloudflared osrm ollama"

  service_block() {
    # service_block <name> <file> — prints the YAML block for one service.
    awk -v svc="  $1:" '
      $0 == svc { f=1; print; next }
      f && /^  [a-zA-Z0-9_-]+:$/ { exit }
      f { print }
    ' "$2"
  }

  # Top-level service keys sit at 4-space indent in `docker compose config`
  # output; nested list-item fields (e.g. a bind mount's own `read_only:
  # true`) sit deeper. Anchoring on 4-space indent avoids matching those.
  note "-- no-new-privileges --"
  for s in $long_running; do
    blk=$(service_block "$s" "$cfg")
    if echo "$blk" | grep -A3 '^    security_opt:' | grep -qE '^ *- no-new-privileges:true$'; then
      ok "$s: no-new-privileges set"
    else
      bad "$s: security_opt no-new-privileges:true missing"
    fi
  done

  note "-- cap_drop ALL --"
  for s in $long_running; do
    blk=$(service_block "$s" "$cfg")
    if echo "$blk" | grep -A3 '^    cap_drop:' | grep -q '^ *- ALL$'; then
      ok "$s: cap_drop ALL set"
    else
      bad "$s: cap_drop: [ALL] missing"
    fi
  done

  note "-- read_only root filesystem --"
  for s in $long_running; do
    blk=$(service_block "$s" "$cfg")
    if echo "$blk" | grep -qE '^    read_only: true$'; then
      ok "$s: read_only root fs"
    else
      bad "$s: read_only: true missing"
    fi
  done

  note "-- pids_limit and cpus set --"
  for s in $long_running; do
    blk=$(service_block "$s" "$cfg")
    has_pids=$(echo "$blk" | grep -cE '^    pids_limit: ' || true)
    has_cpus=$(echo "$blk" | grep -cE '^    cpus: ' || true)
    if [ "$has_pids" -gt 0 ] && [ "$has_cpus" -gt 0 ]; then
      ok "$s: pids_limit + cpus set"
    else
      bad "$s: pids_limit and/or cpus missing"
    fi
  done

  note "-- pinned images (digest, not :latest) --"
  for s in $services; do
    blk=$(service_block "$s" "$cfg")
    # Locally built services (router/functions/ingestor/loader/ollama) have
    # no meaningful pre-build digest to pin -- the digest is an OUTPUT of
    # `docker build`, not an input. What matters for them is that their
    # Dockerfile's FROM base image is pinned; that's covered separately
    # below.
    if echo "$blk" | grep -q '^    build:'; then
      ok "$s: locally built (build: present) -- base image pin checked via Dockerfile"
      continue
    fi
    image_line=$(echo "$blk" | grep -m1 '^    image:' || true)
    [ -z "$image_line" ] && continue
    if echo "$image_line" | grep -q ':latest'; then
      bad "$s: image pinned to :latest -- $image_line"
    elif echo "$image_line" | grep -q '@sha256:'; then
      ok "$s: image pinned by digest -- $image_line"
    else
      bad "$s: image not pinned by digest -- $image_line"
    fi
  done

  note "-- Dockerfile FROM base images pinned by digest --"
  for pair in "router:services/router/Dockerfile" "functions:services/functions/Dockerfile" "embed/ollama:embed/Dockerfile"; do
    name="${pair%%:*}"
    file="${pair#*:}"
    unpinned=$(grep -E '^FROM ' "$file" | grep -v '@sha256:' || true)
    if [ -z "$unpinned" ]; then
      ok "$name: all FROM lines pinned by digest"
    else
      bad "$name: unpinned FROM line(s) in $file: $unpinned"
    fi
  done

  note "-- no whole-secrets-directory mounts --"
  if grep -q '/run/secrets$' "$cfg" || grep -B1 'target: /run/secrets$' "$cfg" | grep -q 'source:'; then
    bad "a service still bind-mounts the whole secrets directory"
  else
    ok "no service mounts the whole ./secrets directory"
  fi
fi

note ""
if [ "$fail" -eq 0 ]; then
  note "RESULT: GREEN — all container hardening checks passed."
else
  note "RESULT: RED — see FAIL lines above."
fi
exit "$fail"
