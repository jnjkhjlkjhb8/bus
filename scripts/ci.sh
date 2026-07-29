#!/usr/bin/env bash
# ci.sh
#
# Canonical entrypoint for the engineering-contract test groups. Both
# `.github/workflows/ci.yaml` and `make verify` call this script for the
# same profiles, so local and CI runs exercise the identical command list —
# the only allowed divergence is caching (CI restores/saves Go/Flutter/pub
# caches; local runs use whatever is already on disk) and report upload
# (CI additionally wraps test runners to emit junit/coverage artifacts for
# Codecov; this script emits those artifacts too when the caller asks for
# them via the env vars below, it just never uploads anything itself).
#
# Usage: scripts/ci.sh <profile> [profile...]
#   contracts   dependency boundaries + file-size ratchet + proto contract +
#               ADR hygiene
#   go          golangci-lint (.golangci.yml, includes govet) + go test
#   flutter     proto-dart stubs + flutter analyze + flutter test
#   migrations  migration replay gate (scripts/check-migrations.sh)
#   security    gitleaks + govulncheck + guardrail-test presence
#   all         every profile above, in the order listed
#
# Report/caching knobs (all optional; unset means "plain local run"):
#   GO_TEST_ARGS       extra args appended to `go test` (CI sets
#                       "-coverprofile=coverage.out" for Codecov)
#   GO_JUNIT_FILE       when set, wraps `go test` with `gotestsum
#                       --junitfile <path>` instead of calling it directly
#                       (gotestsum must already be installed)
#   FLUTTER_TEST_ARGS  extra args appended to `flutter test` (CI sets
#                       "--coverage --file-reporter=json:test-results.json")
#
# Requires generated Go protobuf stubs for the `go` profile (`make
# proto-go`) — this script does not generate them, since which toolchain
# generates them (Docker vs local protoc) differs by caller and is already
# handled by existing Make targets.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/ci.sh <contracts|go|flutter|migrations|security|all> [...]" >&2
  exit 2
fi

run_contracts() {
  echo "== contracts: dependency boundaries =="
  ./scripts/check-dependency-boundaries.sh
  ./scripts/check-dependency-boundaries.sh --self-test
  echo "== contracts: file-size ratchet =="
  ./scripts/check-file-budgets.sh
  ./scripts/check-file-budgets.sh --self-test
  echo "== contracts: proto contract (buf build + breaking) =="
  ./scripts/check-proto-contract.sh
}

run_go() {
  echo "== go: lint (golangci-lint) =="
  make lint

  echo "== go: test =="
  # shellcheck disable=SC2086 # GO_TEST_ARGS is a caller-controlled word list
  if [ -n "${GO_JUNIT_FILE:-}" ]; then
    if ! command -v gotestsum >/dev/null 2>&1; then
      echo "ci.sh: GO_JUNIT_FILE=$GO_JUNIT_FILE set but gotestsum is not installed" >&2
      exit 1
    fi
    gotestsum --junitfile "$GO_JUNIT_FILE" -- -race ${GO_TEST_ARGS:-} ./...
  else
    go test -race ${GO_TEST_ARGS:-} ./...
  fi
}

run_flutter() {
  echo "== flutter: proto-dart stubs =="
  mkdir -p app/lib/data/generated
  PATH="$PATH:$HOME/.pub-cache/bin" protoc --dart_out=grpc:app/lib/data/generated -I models models/*.proto
  echo "== flutter: pub get =="
  (cd app && flutter pub get)
  echo "== flutter: analyze =="
  (cd app && PATH="$PATH:$HOME/.pub-cache/bin" flutter analyze --no-fatal-infos)
  echo "== flutter: test =="
  # shellcheck disable=SC2086 # FLUTTER_TEST_ARGS is a caller-controlled word list
  (cd app && flutter test ${FLUTTER_TEST_ARGS:-})
}

run_migrations() {
  echo "== migrations: replay gate =="
  ./scripts/check-migrations.sh
}

run_security() {
  echo "== security: gitleaks =="
  ./scripts/check-gitleaks.sh
  echo "== security: govulncheck =="
  ./scripts/check-govulncheck.sh
  echo "== security: guardrail tests present =="
  ./scripts/check-guardrail-tests-present.sh
  echo "== security: per-service env allowlist =="
  ./scripts/check-env-allowlist.sh
}

for profile in "$@"; do
  case "$profile" in
    contracts) run_contracts ;;
    go) run_go ;;
    flutter) run_flutter ;;
    migrations) run_migrations ;;
    security) run_security ;;
    all)
      run_contracts
      run_go
      run_flutter
      run_migrations
      run_security
      ;;
    *)
      echo "ci.sh: unknown profile '$profile'" >&2
      exit 2
      ;;
  esac
done
