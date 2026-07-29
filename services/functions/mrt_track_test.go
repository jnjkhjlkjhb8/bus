package main

import (
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

func mrtTestState(current, target, lead int32, status string) *models.MrtTrackState {
	return &models.MrtTrackState{
		TrackId:          "t1",
		TripId:           "201",
		CarId:            "1021",
		PathStationIds:   []string{"BL12", "BL13", "BL14", "BL15", "BL16", "BL17"},
		PathStationNames: []string{"a", "b", "c", "d", "e", "f"},
		TargetIndex:      target,
		CurrentIndex:     current,
		LeadStops:        lead,
		Status:           status,
	}
}

func TestAdvanceMrtTrack(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	recent := now.Add(-time.Minute).Unix()

	cases := []struct {
		name          string
		state         *models.MrtTrackState
		reading       mrtReading
		wantCurrent   int32
		wantRemaining int32
		wantStatus    string
		wantFire      bool
		wantTerminal  bool
	}{
		{
			name:          "advance one hop, above lead",
			state:         mrtTestState(1, 4, 1, mrtStatusTracking),
			reading:       mrtReading{nextIndex: 3, resolved: true, gotInfo: true, hasCountdown: true, countdown: 60 * time.Second},
			wantCurrent:   2,
			wantRemaining: 2,
			wantStatus:    mrtStatusTracking,
			wantFire:      false,
		},
		{
			name:          "reach lead, fire once",
			state:         mrtTestState(1, 4, 2, mrtStatusTracking),
			reading:       mrtReading{nextIndex: 3, resolved: true, gotInfo: true, hasCountdown: true, countdown: 30 * time.Second},
			wantCurrent:   2,
			wantRemaining: 2,
			wantStatus:    mrtStatusLeadFired,
			wantFire:      true,
		},
		{
			// fire is re-requested every tick inside the lead zone; the claim/fired
			// machinery keeps delivery once-only and lets a released (failed) send
			// retry on a later tick.
			name:          "lead_fired keeps requesting fire for claim-level dedup",
			state:         mrtTestState(2, 4, 2, mrtStatusLeadFired),
			reading:       mrtReading{nextIndex: 3, resolved: true, gotInfo: true, hasCountdown: true, countdown: 30 * time.Second},
			wantCurrent:   2,
			wantRemaining: 2,
			wantStatus:    mrtStatusLeadFired,
			wantFire:      true,
		},
		{
			name:          "arrival clamps and fires from tracking",
			state:         mrtTestState(3, 4, 1, mrtStatusTracking),
			reading:       mrtReading{nextIndex: 5, resolved: true, gotInfo: true},
			wantCurrent:   4,
			wantRemaining: 0,
			wantStatus:    mrtStatusArrived,
			wantFire:      true,
			wantTerminal:  true,
		},
		{
			name:         "off-path reading is lost",
			state:        mrtTestState(2, 4, 1, mrtStatusTracking),
			reading:      mrtReading{lost: true},
			wantCurrent:  2,
			wantStatus:   mrtStatusLost,
			wantFire:     false,
			wantTerminal: true,
		},
		{
			// At the end of a run the carID re-trips (new TripId), so a lost reading
			// within one stop of the target is the arrival, not a lost binding —
			// terminal alight stations are common.
			name:         "lost one stop before target is the arrival",
			state:        mrtTestState(3, 4, 1, mrtStatusLeadFired),
			reading:      mrtReading{lost: true},
			wantCurrent:  4,
			wantStatus:   mrtStatusArrived,
			wantFire:     true,
			wantTerminal: true,
		},
		{
			name:          "no advance never moves backward",
			state:         mrtTestState(3, 4, 1, mrtStatusTracking),
			reading:       mrtReading{nextIndex: 2, resolved: true, gotInfo: true},
			wantCurrent:   3,
			wantRemaining: 1,
			wantStatus:    mrtStatusLeadFired,
			wantFire:      true,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			// A recent lastProgress keeps the stale path out of these cases.
			c.state.LastProgressAtUnix = recent
			got, fire := advanceMrtTrack(c.state, c.reading, now)
			if got.CurrentIndex != c.wantCurrent {
				t.Errorf("current = %d want %d", got.CurrentIndex, c.wantCurrent)
			}
			if !c.wantTerminal && got.RemainingStops != c.wantRemaining {
				t.Errorf("remaining = %d want %d", got.RemainingStops, c.wantRemaining)
			}
			if got.Status != c.wantStatus {
				t.Errorf("status = %q want %q", got.Status, c.wantStatus)
			}
			if fire != c.wantFire {
				t.Errorf("fire = %v want %v", fire, c.wantFire)
			}
			if c.wantTerminal && got.NextPollAtUnix != 0 {
				t.Errorf("terminal state should zero next_poll_at, got %d", got.NextPollAtUnix)
			}
			if !c.wantTerminal && got.NextPollAtUnix == 0 {
				t.Errorf("live state should schedule next_poll_at")
			}
		})
	}
}

func TestAdvanceMrtTrackStale(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	state := mrtTestState(2, 5, 1, mrtStatusTracking)
	state.LastProgressAtUnix = now.Add(-11 * time.Minute).Unix()
	// A reading that does not advance the position while the stale window has
	// elapsed ends the session.
	got, fire := advanceMrtTrack(state, mrtReading{}, now)
	if got.Status != mrtStatusStale {
		t.Errorf("status = %q want stale", got.Status)
	}
	if fire {
		t.Error("stale ending must not fire")
	}
	if got.NextPollAtUnix != 0 {
		t.Error("stale ending should zero next_poll_at")
	}
}

func TestAdvanceMrtTrackStaleWhileFinishingIsArrival(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	state := mrtTestState(4, 5, 1, mrtStatusLeadFired)
	state.LastProgressAtUnix = now.Add(-11 * time.Minute).Unix()
	// A stall within one stop of the target (typically a persistently empty
	// GetTrainInfo at the end of a run) reports the ride completed, not stale.
	got, fire := advanceMrtTrack(state, mrtReading{}, now)
	if got.Status != mrtStatusArrived {
		t.Errorf("status = %q want arrived", got.Status)
	}
	if got.CurrentIndex != 5 || got.RemainingStops != 0 {
		t.Errorf("position = %d/%d want clamped to target", got.CurrentIndex, got.RemainingStops)
	}
	if !fire {
		t.Error("arrival inside the lead zone should still request fire (claim dedups)")
	}
	if got.NextPollAtUnix != 0 {
		t.Error("arrived ending should zero next_poll_at")
	}
}

func TestAdvanceMrtTrackProgressAndNextStation(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	state := mrtTestState(0, 4, 1, mrtStatusTracking)
	state.LastProgressAtUnix = now.Add(-time.Minute).Unix()
	got, _ := advanceMrtTrack(state, mrtReading{nextIndex: 2, resolved: true, gotInfo: true}, now)
	if got.CurrentIndex != 1 {
		t.Fatalf("current = %d want 1", got.CurrentIndex)
	}
	if got.Progress != 0.25 {
		t.Errorf("progress = %v want 0.25", got.Progress)
	}
	if got.NextStationId != "BL14" || got.NextStationName != "c" {
		t.Errorf("next station = %s/%s want BL14/c", got.NextStationId, got.NextStationName)
	}
}

func TestParseTrtcTrainCountdown(t *testing.T) {
	cases := []struct {
		in   string
		want time.Duration
		ok   bool
	}{
		{"03:39", 3*time.Minute + 39*time.Second, true},
		{"00:00", 0, true},
		{"12:05", 12*time.Minute + 5*time.Second, true},
		{"列車進站", 0, false},
		{"", 0, false},
		{"4:70", 0, false},
	}
	for _, c := range cases {
		got, ok := parseTrtcTrainCountdown(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("parseTrtcTrainCountdown(%q) = %v,%v want %v,%v", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestMrtResolvePathIndex(t *testing.T) {
	names := []string{"忠孝新生", "忠孝復興", "港墘", "台北車站"}
	cases := []struct {
		stn  string
		want int
	}{
		{"忠孝新生站", 0},
		{"忠孝復興站", 1},
		{"港漧站", 2},    // known misspelling absorbed via alias
		{"台北車站", 3},   // legitimately ends in 站
		{"南京復興站", -1}, // off the stored path
		{"", -1},
		{"站", -1},
	}
	for _, c := range cases {
		if got := mrtResolvePathIndex(names, c.stn); got != c.want {
			t.Errorf("mrtResolvePathIndex(%q) = %d want %d", c.stn, got, c.want)
		}
	}
}

func TestMrtIsTerminal(t *testing.T) {
	for _, s := range []string{mrtStatusArrived, mrtStatusLost, mrtStatusStale, mrtStatusCancelled} {
		if !mrtIsTerminal(s) {
			t.Errorf("%q should be terminal", s)
		}
	}
	for _, s := range []string{mrtStatusTracking, mrtStatusLeadFired} {
		if mrtIsTerminal(s) {
			t.Errorf("%q should not be terminal", s)
		}
	}
}

func TestMrtAdjacencyRows(t *testing.T) {
	lines := []mrtAdjacencyRow{
		{LineID: "BL", TravelTimes: []struct {
			FromStationID string `json:"FromStationID"`
			ToStationID   string `json:"ToStationID"`
		}{
			{FromStationID: "BL12", ToStationID: "BL13"},
			{FromStationID: "BL13", ToStationID: "BL14"},
		}},
	}
	rows := mrtAdjacencyRows(lines, "TRTC")
	// Two segments, both directions each = four directed edges.
	if len(rows) != 4 {
		t.Fatalf("rows = %d want 4", len(rows))
	}
	seen := map[string]bool{}
	for _, r := range rows {
		if r[0] != "TRTC" || r[1] != "BL" {
			t.Errorf("row system/line = %v/%v", r[0], r[1])
		}
		seen[r[2].(string)+"->"+r[3].(string)] = true
	}
	for _, want := range []string{"BL12->BL13", "BL13->BL12", "BL13->BL14", "BL14->BL13"} {
		if !seen[want] {
			t.Errorf("missing directed edge %s", want)
		}
	}
}
