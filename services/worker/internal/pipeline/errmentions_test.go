package pipeline

import (
	"errors"
	"fmt"
	"strings"

	"github.com/samber/oops"
)

// errMentions reports whether every whitespace-separated token of want appears
// in err's message or among the oops attributes carried along its error chain.
// Structured errors keep messages low-cardinality and put variable data in
// attributes, so an assertion about "which field was rejected" has to look in
// both places. oops merges the whole chain's context, so one errors.As is enough.
func errMentions(err error, want string) bool {
	if err == nil {
		return false
	}
	haystack := []string{err.Error()}
	var structured oops.OopsError
	if errors.As(err, &structured) {
		for key, value := range structured.Context() {
			haystack = append(haystack, key, fmt.Sprint(value))
		}
	}
	for _, token := range strings.Fields(want) {
		found := false
		for _, candidate := range haystack {
			if strings.Contains(candidate, token) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
