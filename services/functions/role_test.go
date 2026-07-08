package main

import "testing"

// Covers: ROLE="" → legacy prod, ROLE=ingestor → ingestor, ROLE=loader → loader,
// and that eta/realtime/etl/unknown all error out instead of falling into the
// legacy prod flow (so they never initialize Firebase / dispatcher / MQTT, which
// live only in runLegacyProd).
func TestResolveRole(t *testing.T) {
	okCases := map[string]appMode{
		"":         modeLegacyProd,
		"ingestor": modeIngestor,
		"loader":   modeLoader,
	}
	for role, want := range okCases {
		got, err := resolveRole(role)
		if err != nil {
			t.Errorf("resolveRole(%q) unexpected error: %v", role, err)
		}
		if got != want {
			t.Errorf("resolveRole(%q) = %v, want %v", role, got, want)
		}
	}
	for _, role := range []string{"eta", "realtime", "etl", "bogus", "INGESTOR", "Ingestor"} {
		if _, err := resolveRole(role); err == nil {
			t.Errorf("resolveRole(%q) expected error, got nil", role)
		}
	}
	// eta/etl must not resolve to the legacy prod mode.
	for _, role := range []string{"eta", "realtime", "etl"} {
		if got, _ := resolveRole(role); got == modeLegacyProd {
			t.Errorf("resolveRole(%q) must not be modeLegacyProd", role)
		}
	}
}

func TestDBSinceFallbackAllowed(t *testing.T) {
	defer func() { rawDumpEnabled = false }()
	rawDumpEnabled = true
	if dbSinceFallbackAllowed() {
		t.Error("ingestor mode must NOT fall back to dbSince (would 304 an empty raw_tdx)")
	}
	rawDumpEnabled = false
	if !dbSinceFallbackAllowed() {
		t.Error("legacy prod must allow dbSince fallback")
	}
}
