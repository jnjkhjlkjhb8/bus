package bus

import (
	"sort"
	"strconv"
	"strings"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

// convergenceViolation is one canonical UID that failed the ADR-0006 merge
// invariant: issue is "too_many_directions" or "name_mismatch".
type convergenceViolation struct {
	canonical string
	issue     string
	detail    string
}

// findConvergenceViolations remains a focused diagnostic helper for ADR-0006.
// The atomic snapshot reader now rejects divergent variants before any target
// write; this helper is retained for the explicit invariant tests and audit
// tooling that summarize an already assembled map.
func findConvergenceViolations(subRoutemap map[string]*models.BusSubroute, nameObs map[string]map[string]struct{}) []convergenceViolation {
	var out []convergenceViolation
	for uid, sub := range subRoutemap {
		if n := len(sub.Directions); n > 2 {
			out = append(out, convergenceViolation{uid, "too_many_directions", strconv.Itoa(n)})
		}
	}
	for uid, names := range nameObs {
		if len(names) > 1 {
			distinct := make([]string, 0, len(names))
			for name := range names {
				distinct = append(distinct, name)
			}
			sort.Strings(distinct)
			out = append(out, convergenceViolation{uid, "name_mismatch", strings.Join(distinct, "|")})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].canonical != out[j].canonical {
			return out[i].canonical < out[j].canonical
		}
		return out[i].issue < out[j].issue
	})
	return out
}
