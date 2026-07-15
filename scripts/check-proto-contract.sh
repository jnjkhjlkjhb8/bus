#!/usr/bin/env bash
# check-proto-contract.sh
#
# API-contract gate for models/*.proto, using buf pinned to a fixed version
# (installed hermetically into .tools/bin via `go install pkg@version`, the
# same pattern the Makefile uses for protoc-gen-go — never @latest):
#
#   1. `buf build` — the proto set compiles into a valid image (a stronger
#      well-formedness check than protoc alone).
#   2. `buf breaking` — no wire-breaking change (field renumbering, type
#      changes, message/RPC removal, ...) relative to a git baseline.
#      Default baseline is HEAD, catching breaking edits before they are
#      committed; CI passes PROTO_BASELINE_REF=<base branch> to compare a
#      PR against its merge base instead.
#
# `buf lint` is deliberately NOT enforced: the existing wire contract bakes
# in 324 style violations (no package declarations, PascalCase field names,
# lowercase RPC names). Renaming would be wire-compatible but would break
# every generated Go/Dart call site for zero contract value, and excepting
# nearly every lint rule would make the gate meaningless. Wire safety is
# what matters, and `buf breaking` covers it.
#
# Usage: scripts/check-proto-contract.sh
#   PROTO_BASELINE_REF  git ref to diff the contract against (default HEAD)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

BUF_VERSION="v1.71.0"
tools_bin="$repo_root/.tools/bin"
baseline_ref="${PROTO_BASELINE_REF:-HEAD}"

echo "== proto contract (buf $BUF_VERSION, baseline: $baseline_ref) =="

mkdir -p "$tools_bin"
if ! "$tools_bin/buf" --version 2>/dev/null | grep -qx "${BUF_VERSION#v}"; then
  echo "  installing buf $BUF_VERSION into .tools/bin"
  GOBIN="$tools_bin" go install "github.com/bufbuild/buf/cmd/buf@$BUF_VERSION"
fi

fail=0

if "$tools_bin/buf" build models -o /dev/null; then
  echo "  OK   buf build: models/*.proto compile into a valid image"
else
  echo "  FAIL buf build: models/*.proto do not compile"
  fail=1
fi

if ! git rev-parse --verify --quiet "$baseline_ref^{commit}" >/dev/null; then
  echo "  FAIL baseline ref '$baseline_ref' does not resolve to a commit"
  fail=1
elif "$tools_bin/buf" breaking models --against ".git#ref=$baseline_ref,subdir=models"; then
  echo "  OK   buf breaking: wire contract unchanged vs $baseline_ref"
else
  echo "  FAIL buf breaking: wire-breaking proto change vs $baseline_ref (see lines above)"
  fail=1
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "RESULT: GREEN — proto contract intact."
else
  echo "RESULT: RED — see FAIL lines above."
fi
exit "$fail"
