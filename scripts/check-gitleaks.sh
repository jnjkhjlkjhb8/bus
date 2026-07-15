#!/usr/bin/env bash
# check-gitleaks.sh
#
# Secret scan over the tracked tree using gitleaks pinned to a fixed version
# (hermetic `go install pkg@version` into .tools/bin, never @latest).
#
# The scan target is a `git archive HEAD` extraction, not the working tree:
# real env files (env/*.env) are gitignored but sit in local checkouts with
# live credentials, and scanning them would light up findings for secrets
# that are deliberately kept out of git. The archive contains exactly what
# a clone (and CI) sees. Findings are printed with --redact, so secret
# values never reach the log — file, line, and rule only.
#
# CI runs gitleaks/gitleaks-action (pinned by commit SHA in ci.yaml) over
# commit history as the blocking gate; this script is the same policy for
# `make verify` on a developer machine.
#
# Usage: scripts/check-gitleaks.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

GITLEAKS_VERSION="v8.30.1"
tools_bin="$repo_root/.tools/bin"

echo "== gitleaks secret scan ($GITLEAKS_VERSION, tracked tree) =="

mkdir -p "$tools_bin"
# A `go install` build does not stamp `gitleaks version`; read the module
# version from the binary's build info instead.
if ! go version -m "$tools_bin/gitleaks" 2>/dev/null \
  | grep -q "github.com/zricethezav/gitleaks/v8[[:space:]]*$GITLEAKS_VERSION"; then
  echo "  installing gitleaks $GITLEAKS_VERSION into .tools/bin"
  GOBIN="$tools_bin" go install "github.com/zricethezav/gitleaks/v8@$GITLEAKS_VERSION"
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
git archive HEAD | tar -x -C "$work_dir"

# Config is taken from the working tree (not the archive) so a policy edit
# is testable before it is committed.
if "$tools_bin/gitleaks" dir "$work_dir" --config "$repo_root/.gitleaks.toml" \
  --no-banner --redact --exit-code 1; then
  echo "  OK   no secrets detected in the tracked tree"
  echo ""
  echo "RESULT: GREEN — gitleaks found no leaks."
else
  echo "  FAIL gitleaks flagged findings above (values redacted; rotate + purge, or add a reviewed .gitleaksignore entry)"
  echo ""
  echo "RESULT: RED — secrets detected."
  exit 1
fi
