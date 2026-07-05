package shared

import "testing"

func TestCanonicalSubroute(t *testing.T) {
	cases := []struct {
		name    string
		city    string
		uid     string
		inDir   uint8
		wantUID string
		wantDir uint8
	}{
		{"intercity 01 suffix", "InterCity", "THB902301", 9, "THB9023", 0},
		{"intercity 02 suffix", "InterCity", "THB902302", 9, "THB9023", 1},
		{"intercity trailing-digit A1", "InterCity", "THB9023A1", 3, "THB9023A", 3},
		{"intercity trailing-digit A0", "InterCity", "THB9023A0", 5, "THB9023A", 5},
		{"non-intercity passthrough", "Taipei", "TPE1234", 1, "TPE1234", 1},
		{"intercity short uid safe", "InterCity", "X", 1, "X", 1},
		{"intercity empty uid safe", "InterCity", "", 0, "", 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotUID, gotDir := CanonicalSubroute(tc.city, tc.uid, tc.inDir)
			if gotUID != tc.wantUID || gotDir != tc.wantDir {
				t.Fatalf("CanonicalSubroute(%q, %q, %d) = (%q, %d), want (%q, %d)",
					tc.city, tc.uid, tc.inDir, gotUID, gotDir, tc.wantUID, tc.wantDir)
			}
		})
	}
}
