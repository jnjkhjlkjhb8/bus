#!/usr/bin/env bash
# check-compose-isolation.sh
#
# Expands the staging and prod Compose configs (using their tracked example
# env files) and asserts the two deployments cannot collide when run on the
# same host: distinct Compose project names, distinct published host ports,
# distinct named-volume identities, loopback ingress by default, and
# agreement between server-side GRPC_TLS and the matching app flavor JSON.
#
# `docker compose config` output is written to files under a private temp
# directory and never printed in full — only the specific asserted keys are
# grepped out — because BUS_ENV_FILE-driven expansion can pull in whatever
# secrets the env file holds. The tracked *.env.example files used here only
# ever contain placeholders, but the script is written so it stays safe if
# ever pointed at a real env file.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fail=0
note() { printf '%s\n' "$*"; }
ok() { printf '  OK   %s\n' "$*"; }
bad() {
  printf '  FAIL %s\n' "$*"
  fail=1
}

expand() {
  # expand <env-name> <compose-override-file> <env-example-file> <project-name>
  local env_name="$1" override="$2" env_file="$3" project="$4"
  local out="$work_dir/${env_name}.yaml"
  if ! BUS_ENV_FILE="$env_file" docker compose \
    --project-directory . \
    -p "$project" \
    --env-file "$env_file" \
    -f docker/docker-compose.yaml \
    -f "$override" \
    config >"$out" 2>"$work_dir/${env_name}.err"; then
    cat "$work_dir/${env_name}.err" >&2
    exit 1
  fi
  echo "$out"
}

note "== Expanding configs =="
test_cfg=$(expand test docker/docker-compose.test.yaml env/test.env.example bus-test)
staging_cfg=$(expand staging docker/docker-compose.staging.yaml env/staging.env.example bus-staging)
prod_cfg=$(expand prod docker/docker-compose.prod.yaml env/prod.env.example bus-prod)
note "  wrote $test_cfg, $staging_cfg, $prod_cfg"

project_name() { grep -m1 '^name:' "$1" | awk '{print $2}'; }
test_name=$(project_name "$test_cfg")
staging_name=$(project_name "$staging_cfg")
prod_name=$(project_name "$prod_cfg")

note ""
note "== Distinct project names =="
if [ "$staging_name" != "$prod_name" ] && [ "$test_name" != "$staging_name" ] && [ "$test_name" != "$prod_name" ]; then
  ok "test=$test_name staging=$staging_name prod=$prod_name"
else
  bad "project names collide: test=$test_name staging=$staging_name prod=$prod_name"
fi

# published_ports <file> -> lines of "host_ip:published" (one per port entry),
# reading the ordered host_ip/target/published triples under each service.
published_ports() {
  awk '
    /^ *ports:/ { in_ports=1; next }
    in_ports && /^ *- /  { next }
    in_ports && /^ *host_ip:/ { ip=$2; next }
    in_ports && /^ *published:/ { pub=$2; gsub(/"/,"",pub); print (ip=="" ? "0.0.0.0" : ip) ":" pub; ip=""; next }
    in_ports && /^ *[a-z_]+:$/ && !/^ *(mode|target|published|protocol|host_ip):/ { in_ports=0 }
  ' "$1" | sort -u
}

note ""
note "== Distinct published host ports (staging vs prod) =="
staging_ports=$(published_ports "$staging_cfg")
prod_ports=$(published_ports "$prod_cfg")
overlap=$(comm -12 <(echo "$staging_ports") <(echo "$prod_ports") || true)
if [ -z "$overlap" ]; then
  ok "no overlapping host_ip:port pairs"
else
  bad "overlapping published ports between staging and prod: $overlap"
fi

note ""
note "== Loopback ingress defaults (staging) =="
non_loopback=$(echo "$staging_ports" | grep -v '^127\.0\.0\.1:' || true)
if [ -z "$non_loopback" ]; then
  ok "all staging published ports bind to 127.0.0.1"
else
  bad "staging publishes on a non-loopback address: $non_loopback"
fi

note ""
note "== Distinct named-volume identities =="
volume_names() {
  awk '/^volumes:/{f=1} f' "$1" | grep 'name:' | awk '{print $2}' | sort -u
}
staging_volumes=$(volume_names "$staging_cfg")
prod_volumes=$(volume_names "$prod_cfg")
vol_overlap=$(comm -12 <(echo "$staging_volumes") <(echo "$prod_volumes") || true)
if [ -n "$staging_volumes" ] && [ -n "$prod_volumes" ] && [ -z "$vol_overlap" ]; then
  ok "staging volumes {$staging_volumes} disjoint from prod volumes {$prod_volumes}"
else
  bad "volume identities missing or colliding: staging={$staging_volumes} prod={$prod_volumes}"
fi

note ""
note "== TLS/plaintext agreement: server env vs app flavor JSON =="
check_tls_agreement() {
  local env_name="$1" env_file="$2" app_json="$3"
  local server_tls app_tls
  server_tls=$(grep -m1 '^GRPC_TLS=' "$env_file" | cut -d= -f2)
  app_tls=$(grep -m1 '"GRPC_TLS"' "$app_json" | grep -o 'true\|false')
  if [ "$server_tls" != "$app_tls" ]; then
    bad "$env_name: server GRPC_TLS=$server_tls but app flavor GRPC_TLS=$app_tls"
    return
  fi
  if [ "$server_tls" = "true" ]; then
    local cert key
    cert=$(grep -m1 '^GRPC_TLS_CERT_FILE=' "$env_file" | cut -d= -f2)
    key=$(grep -m1 '^GRPC_TLS_KEY_FILE=' "$env_file" | cut -d= -f2)
    if [ -z "$cert" ] || [ -z "$key" ]; then
      bad "$env_name: GRPC_TLS=true but GRPC_TLS_CERT_FILE/GRPC_TLS_KEY_FILE unset"
      return
    fi
  fi
  ok "$env_name: server GRPC_TLS=$server_tls agrees with app flavor GRPC_TLS=$app_tls"
}
check_tls_agreement test env/test.env.example app/env/test.json.example
check_tls_agreement staging env/staging.env.example app/env/staging.json.example
check_tls_agreement prod env/prod.env.example app/env/prod.json.example

note ""
if [ "$fail" -eq 0 ]; then
  note "RESULT: GREEN — all compose isolation checks passed."
else
  note "RESULT: RED — see FAIL lines above."
fi
exit "$fail"
