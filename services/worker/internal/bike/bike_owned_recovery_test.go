package bike

import (
	"context"
	"errors"
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/busmodel"
)

// TestUnwatchedBikeRefreshFailureDropsCadenceClaim covers the one path that
// calls refreshOwnedTTL outside bindFetch, and so has no 304 to invalidate a
// marker from: an unwatched city whose owned keys have expired (a restart longer
// than pipeline.BikeLiveTTL leaves the 24h ownership set pointing at nothing).
//
// Re-arming cannot bring those keys back, so the recovery is to drop the cadence
// claim and let the gate open. Without it the city never fetches and the failure
// repeats every tick until the ownership set itself expires.
func TestUnwatchedBikeRefreshFailureDropsCadenceClaim(t *testing.T) {
	refreshErr := errors.New("ownership set contains missing live keys")
	sink := &captureLiveSink{
		strings:    map[string]string{},
		owned:      map[string][]string{},
		refreshErr: refreshErr,
	}
	// Every city holds a cadence claim and no demand key, so the gate closes on
	// all of them and no fetch is reachable. Only Taipei owns keys, so only
	// Taipei's refresh runs and fails.
	for _, city := range busmodel.Cities {
		sink.strings[shared.LiveColdKey("bike", city)] = "1"
	}
	owner := shared.LiveOwnedKeysKey("bike", "Taipei")
	sink.owned[owner] = []string{shared.BikeAvailabilityKey("TPE-GONE")}

	fetch := func(context.Context, string, string) (*shared.TDXFetch, error) {
		t.Fatal("gated city was fetched")
		return nil, nil
	}
	err := Eta(context.Background(), fetch, sink, nil)
	if !errors.Is(err, refreshErr) {
		t.Fatalf("Eta error = %v, want it to wrap %v", err, refreshErr)
	}

	coldKey := shared.LiveColdKey("bike", "Taipei")
	var dropped bool
	for _, expire := range sink.expires {
		if expire.key == coldKey {
			if expire.ttl != 0 {
				t.Fatalf("cadence claim %s expired with ttl %v, want 0 (delete)", coldKey, expire.ttl)
			}
			dropped = true
		}
	}
	if !dropped {
		t.Fatalf("cadence claim %s was not dropped; expires = %v", coldKey, sink.expires)
	}
	// The set itself must survive: the full fetch that follows replaces it
	// atomically, and deleting it here would hide the failure from that retry.
	if got := sink.owned[owner]; len(got) != 1 {
		t.Fatalf("ownership set = %v, want left intact", got)
	}
}
