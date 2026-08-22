#!/usr/bin/env bash
# check-guardrail-tests-present.sh
#
# The substantive fault-injection, cancellation/overlap, and authenticated-
# metrics tests live with their subsystems (added by earlier remediation
# tasks). This check only asserts they have not silently vanished: each
# named test file must still exist AND its anchor tests must still be
# selected by `go test -run` (a deleted or renamed test would report
# "no tests to run" / build failure here long before anyone notices the
# coverage gap). It deliberately does not re-run the full suites.
#
# DB-dependent anchors skip themselves when DATABASE_URL is unset — a skip
# still proves the test exists, compiles, and is wired into the suite.
#
# Accessibility text-scale/semantics matrix: no such Flutter test exists in
# app/test yet; the gate for it lands with the Flutter accessibility task.
# Tracked here as a WARN so the gap stays visible without failing builds.
#
# Requires generated protobuf stubs (run via `make verify`, after proto-go).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0
warn=0
note() { printf '\n== %s ==\n' "$*"; }
ok() { printf '  OK   %s\n' "$*"; }
bad() {
  printf '  FAIL %s\n' "$*"
  fail=1
}
warning() {
  printf '  WARN %s\n' "$*"
  warn=1
}

# anchor <category> <file> <package> <run-regex>
anchor() {
  local category="$1" file="$2" pkg="$3" run_re="$4" out
  if [ ! -f "$file" ]; then
    bad "$category: $file is gone"
    return
  fi
  if ! out="$(go test -count=1 -run "$run_re" "$pkg" 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/       /'
    bad "$category: anchor tests in $file failed ($run_re)"
    return
  fi
  if printf '%s' "$out" | grep -q 'no tests to run'; then
    bad "$category: $file exists but no test matches '$run_re' (renamed without updating this gate?)"
    return
  fi
  ok "$category: $file ($run_re)"
}

note "guardrail test presence + smoke run"
anchor "fault-injection/atomicity" \
  services/worker/internal/raw/landing_state_test.go ./services/worker/internal/raw \
  'TestLandRawTDXCommitsRowsAndStateAtomically'
anchor "fault-injection/atomicity" \
  services/worker/notify/notification_store_test.go ./services/worker/notify \
  'TestNotificationStoreClaimIsAtomic'
anchor "cancellation/overlap" \
  services/worker/job_runner_test.go ./services/worker \
  'TestBootRunUsesTimeoutAndSameOverlapGuard|TestStaticPipelineReleasesAfterCancellationAndPanic'
anchor "authenticated metrics" \
  services/api/http_test.go ./services/api \
  'TestMetricsRequiresConfiguredCredential|TestMetricsAuthenticationPrecedesPrincipalRateLimit|TestMetricsBearerParsingAndSecurityHeaders'

note "accessibility matrix"
if ls app/test/**/*accessibility*_test.dart app/test/**/*semantics*_test.dart >/dev/null 2>&1; then
  ok "Flutter accessibility tests present"
else
  warning "no text-scale/semantics matrix under app/test yet (tracked gap; owned by the Flutter accessibility task)"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "RESULT: GREEN — all guardrail anchor tests present and passing."
else
  echo "RESULT: RED — see FAIL lines above."
fi
exit "$fail"
