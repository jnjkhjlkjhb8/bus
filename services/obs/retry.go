package obs

import (
	"context"
	"errors"
	"time"
)

// Retry calls fn up to attempts times, retrying only when the returned error
// wraps ErrTransient (see Transient); any other error, including nil, returns
// immediately so non-retryable failures are not masked by repeated calls.
// Between attempts it sleeps with exponential backoff (base, 2*base, 4*base,
// ...) via base<<(i-1), and aborts with ctx.Err() if the context is cancelled
// during a wait. The last observed error is returned once attempts run out.
func Retry(ctx context.Context, attempts int, base time.Duration, fn func() error) error {
	var err error
	for i := range attempts {
		if i > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(base << (i - 1)):
			}
		}
		err = fn()
		if err == nil || !errors.Is(err, ErrTransient) {
			return err
		}
	}
	return err
}
