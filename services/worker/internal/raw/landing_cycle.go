package raw

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"time"
)

// LandingCycleSource is the stronger, additive source contract used only by
// the correlated bus snapshot. JSON bytes, freshness, and the durable landing
// cycle are read from one RepeatableRead transaction. Other loaders retain the
// smaller pipeline.LoadSource contract and do not acquire cycle coupling accidentally.
type LandingCycleSource interface {
	DatasetJSONWithLandingCycle(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, string, error)
}

// IsStale reports whether a partition landed at fetchedAt is too old to load.
func IsStale(fetchedAt time.Time) bool {
	return time.Since(fetchedAt) > StaleAfter
}

func NewLandingCycle() (string, error) {
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", _oops.Wrapf(err, "generate random identity")
	}
	return hex.EncodeToString(random[:]), nil
}

// StaleAfter is the freshness window. Landing runs at 03:00, loads at 03:30; a
// partition older than 27h means the last landing failed or was skipped, so the
// loader leaves the env schema untouched (ADR-0005 coordination).
const StaleAfter = 27 * time.Hour
