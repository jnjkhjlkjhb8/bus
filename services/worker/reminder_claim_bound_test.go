package main

import (
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/notify"
)

// TestReminderClaimTimeoutExceedsInFlightSendBound links three constants that
// live in different files with nothing else tying them together: the reclaim
// safety argument is that a 'sending' claim older than
// notify.ReminderClaimTimeout cannot belong to a live sender, because every
// dispatch runs under liveJobTimeout (live.go) and its detached finalization
// under notify.ArrivalFinalizationTimeout (notifications.go). If this
// inequality breaks, a reclaimer can take a row whose original sender is still
// in flight, and the same reminder is pushed twice.
func TestReminderClaimTimeoutExceedsInFlightSendBound(t *testing.T) {
	if _liveJobTimeout+notify.ArrivalFinalizationTimeout >= notify.ReminderClaimTimeout {
		t.Fatalf(
			"liveJobTimeout (%v) + notify.ArrivalFinalizationTimeout (%v) must stay below notify.ReminderClaimTimeout (%v): otherwise a 'sending' reminder can be reclaimed while its original send is still in flight, double-sending the push",
			_liveJobTimeout, notify.ArrivalFinalizationTimeout, notify.ReminderClaimTimeout,
		)
	}
}
