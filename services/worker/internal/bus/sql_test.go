package bus

import (
	"strings"
	"testing"
)

func TestBusSubroutesUpsertDeduplicatesConflictKeys(t *testing.T) {
	if !strings.Contains(_busSubroutesUpsertSQL, "SELECT DISTINCT ON (uid, d)") {
		t.Fatalf("bus_subroutes upsert SQL missing DISTINCT ON dedup")
	}
}

// TestBusScheduleInsertKeepsDuplicates locks in the partition-replace contract:
// bus_schedule is rebuilt per city by DELETE + plain INSERT, so the schedule
// insert must NOT dedup (no DISTINCT ON) and must NOT upsert (no ON CONFLICT).
// A circular route visits the same stop twice per trip, colliding on the old
// natural key; those rows are intentionally kept now.
func TestBusScheduleInsertKeepsDuplicates(t *testing.T) {
	for _, banned := range []string{"DISTINCT ON", "ON CONFLICT"} {
		if strings.Contains(_busScheduleInsertSQL, banned) {
			t.Fatalf("bus_schedule insert SQL must not contain %q (partition-replace keeps duplicate rows)", banned)
		}
	}
}
