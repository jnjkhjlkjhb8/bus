package main

import (
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

func TestAdjustedEstimate(t *testing.T) {
	now := time.Date(2026, 7, 10, 8, 0, 30, 0, time.UTC)
	tests := []struct {
		name string
		eta  rawBusEsimated
		want int32
	}{
		{
			name: "unparseable src time keeps raw estimate",
			eta:  rawBusEsimated{EstimatedTime: 120, SrcUpdateTime: ""},
			want: 120,
		},
		{
			name: "stale src time ages estimate forward",
			eta:  rawBusEsimated{EstimatedTime: 120, SrcUpdateTime: "2026-07-10T08:00:00Z"},
			want: 90, // 120 - 30s of snapshot age
		},
		{
			name: "fresh src time equal to now leaves estimate",
			eta:  rawBusEsimated{EstimatedTime: 60, SrcUpdateTime: "2026-07-10T08:00:30Z"},
			want: 60,
		},
		{
			name: "snapshot older than its estimate clamps to zero",
			eta:  rawBusEsimated{EstimatedTime: 10, SrcUpdateTime: "2026-07-10T08:00:00Z"},
			want: 0,
		},
		{
			name: "negative estimate from tdx clamps to zero",
			eta:  rawBusEsimated{EstimatedTime: -5, SrcUpdateTime: ""},
			want: 0,
		},
		{
			name: "zoneless src time reads as taipei local",
			eta:  rawBusEsimated{EstimatedTime: 120, SrcUpdateTime: "2026-07-10T16:00:00"},
			want: 90, // 16:00 +08:00 == 08:00Z, 30s before now
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := adjustedEstimate(tt.eta, now); got != tt.want {
				t.Fatalf("adjustedEstimate() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestBuildBusEtaMap(t *testing.T) {
	t.Run("collisions resolve via pickBusEstimate", func(t *testing.T) {
		eat := []rawBusEsimated{
			{SubRouteUID: "R1", Direction: 0, StopUID: "S1", StopStatus: 1, EstimatedTime: 10},
			{SubRouteUID: "R1", Direction: 0, StopUID: "S1", StopStatus: 0, EstimatedTime: 300},
			{SubRouteUID: "R1", Direction: 0, StopUID: "S2", StopStatus: 1, EstimatedTime: 45},
		}
		m := buildBusEtaMap("Taipei", eat, nil)
		if len(m) != 2 {
			t.Fatalf("len = %d, want 2", len(m))
		}
		got := m[etaKey{"R1", 0, "S1"}]
		if got.StopStatus != 0 || got.EstimatedTime != 300 {
			t.Fatalf("S1 = %+v, want status 0 est 300 (en-route wins)", got)
		}
	})

	t.Run("InterCity canonicalizes subroute suffix", func(t *testing.T) {
		eat := []rawBusEsimated{
			{SubRouteUID: "ABC01", Direction: 9, StopUID: "S1", EstimatedTime: 60},
			{SubRouteUID: "ABC02", Direction: 9, StopUID: "S1", EstimatedTime: 90},
		}
		m := buildBusEtaMap("InterCity", eat, nil)
		if _, ok := m[etaKey{"ABC", 0, "S1"}]; !ok {
			t.Errorf("missing canonical outbound key ABC/0")
		}
		if _, ok := m[etaKey{"ABC", 1, "S1"}]; !ok {
			t.Errorf("missing canonical inbound key ABC/1")
		}
	})

	// Taipei/NewTaipei publish arrivals with RouteUID only. Route 261 (TPE10414)
	// has two subroutes; each must pick up the route-level entry, but only for the
	// stops it actually serves.
	t.Run("route-level entry fans out to the route's subroutes", func(t *testing.T) {
		mp := []busStationmap{
			{SubRouteUID: "TPE104140", RouteUID: "TPE10414", Direction: 1, StopUID: "S1"},
			{SubRouteUID: "TPE104140", RouteUID: "TPE10414", Direction: 1, StopUID: "S2"},
			{SubRouteUID: "TPE162278", RouteUID: "TPE10414", Direction: 1, StopUID: "S1"},
			{SubRouteUID: "TPE999990", RouteUID: "TPE99999", Direction: 1, StopUID: "S9"},
		}
		eat := []rawBusEsimated{
			{RouteUID: "TPE10414", Direction: 1, StopUID: "S1", StopStatus: 0, EstimatedTime: 240},
		}
		m := buildBusEtaMap("Taipei", eat, mp)
		for _, sub := range []string{"TPE104140", "TPE162278"} {
			got, ok := m[etaKey{sub, 1, "S1"}]
			if !ok {
				t.Fatalf("subroute %s did not pick up the route-level arrival", sub)
			}
			if got.EstimatedTime != 240 {
				t.Errorf("%s estimate = %d, want 240", sub, got.EstimatedTime)
			}
		}
		if _, ok := m[etaKey{"TPE104140", 1, "S2"}]; ok {
			t.Error("fan-out invented an arrival at S2, which the feed never reported")
		}
		if _, ok := m[etaKey{"TPE999990", 1, "S1"}]; ok {
			t.Error("fan-out leaked the arrival to an unrelated route")
		}
	})

	// A feed that does carry SubRouteUID must not also fan out by RouteUID, or one
	// subroute's arrival would be copied onto its siblings.
	t.Run("subroute-level entry does not fan out", func(t *testing.T) {
		mp := []busStationmap{
			{SubRouteUID: "KEE015801", RouteUID: "KEE0158", Direction: 0, StopUID: "S1"},
			{SubRouteUID: "KEE015802", RouteUID: "KEE0158", Direction: 0, StopUID: "S1"},
		}
		eat := []rawBusEsimated{
			{SubRouteUID: "KEE015801", RouteUID: "KEE0158", Direction: 0, StopUID: "S1", EstimatedTime: 60},
		}
		m := buildBusEtaMap("Keelung", eat, mp)
		if _, ok := m[etaKey{"KEE015802", 0, "S1"}]; ok {
			t.Error("sibling subroute picked up an arrival that named a specific subroute")
		}
	})
}

func TestBuildBusPositionMap(t *testing.T) {
	posit := []rawBusPosition{
		{PlateNumb: "AAA-1", SubRouteUID: "R1", Direction: 0, Speed: 42.7, Azimuth: 180},
		{PlateNumb: "AAA-2", SubRouteUID: "R1", Direction: 0, Speed: 0, Azimuth: 90},
		{PlateNumb: "WRONG-WAY", SubRouteUID: "R1", Direction: 1, Speed: 9, Azimuth: 270},
		{PlateNumb: "BBB-1", SubRouteUID: "R2", Direction: 1, Speed: 10, Azimuth: 0},
	}
	posit[0].BusPosition.PositionLon = 121.5
	posit[0].BusPosition.PositionLat = 25.0
	m := buildDirectionAwareBusPositionMap("Taipei", posit)
	if len(m["R1\x000"]) != 2 {
		t.Fatalf("R1 direction 0 buses = %d, want 2", len(m["R1\x000"]))
	}
	if len(m["R1\x001"]) != 1 || m["R1\x001"][0].PlateNumb != "WRONG-WAY" {
		t.Fatalf("R1 direction 1 buses = %+v, want WRONG-WAY only", m["R1\x001"])
	}
	if len(m["R2\x001"]) != 1 {
		t.Fatalf("R2 direction 1 buses = %d, want 1", len(m["R2\x001"]))
	}
	first := m["R1\x000"][0]
	if first.PlateNumb != "AAA-1" || first.Speed != 42 || first.Azimuth != 180 {
		t.Errorf("first R1 bus = %+v, want plate AAA-1 speed 42 azimuth 180 (float truncated)", first)
	}
	if first.PositionLon != 121.5 || first.PositionLat != 25.0 {
		t.Errorf("first R1 bus position = (%v,%v), want (121.5,25.0)", first.PositionLon, first.PositionLat)
	}
}

func TestParseGPSTimeUnix(t *testing.T) {
	// +08:00 offset (the common TDX form) and a zone-less string read as Taipei
	// both resolve to the same instant; junk and empty fall back to 0.
	want := time.Date(2026, 7, 13, 8, 30, 0, 0, taipei).Unix()
	cases := map[string]int64{
		"2026-07-13T08:30:00+08:00": want,
		"2026-07-13T08:30:00":       want,
		"2026-07-13 08:30:00":       want,
		"":                          0,
		"not-a-time":                0,
	}
	for in, exp := range cases {
		if got := parseGPSTimeUnix(in); got != exp {
			t.Errorf("parseGPSTimeUnix(%q) = %d, want %d", in, got, exp)
		}
	}
}

func TestBuildTotalStops(t *testing.T) {
	mp := []busStationmap{
		{SubRouteUID: "R1", Direction: 0, StopUID: "S1"},
		{SubRouteUID: "R1", Direction: 0, StopUID: "S2"},
		{SubRouteUID: "R1", Direction: 0, StopUID: "S3"},
		{SubRouteUID: "R2", Direction: 1, StopUID: "S1"},
	}
	got := buildTotalStops("Taipei", mp)
	if got["R1"] != 3 {
		t.Errorf("R1 = %d, want 3", got["R1"])
	}
	if got["R2"] != 1 {
		t.Errorf("R2 = %d, want 1", got["R2"])
	}
}

func TestCollectFillKeys(t *testing.T) {
	mp := []busStationmap{
		{SubRouteUID: "R1", Direction: 0, StopUID: "S1"}, // status 1, gap → fill
		{SubRouteUID: "R1", Direction: 0, StopUID: "S2"}, // status 0, en route → fill
		{SubRouteUID: "R1", Direction: 0, StopUID: "S3"}, // status 1 with NextBusTime → skip
		{SubRouteUID: "R2", Direction: 1, StopUID: "S1"}, // no eta entry → skip
	}
	etamap := map[etaKey]rawBusEsimated{
		{"R1", 0, "S1"}: {StopStatus: 1, NextBusTime: ""},
		{"R1", 0, "S2"}: {StopStatus: 0},
		{"R1", 0, "S3"}: {StopStatus: 1, NextBusTime: "2026-07-10T08:05:00Z"},
	}
	keys, uids := collectFillKeys("Taipei", mp, etamap)
	if len(keys) != 2 {
		t.Fatalf("fillKeys = %d (%v), want 2", len(keys), keys)
	}
	for _, k := range keys {
		if k != (routeDirKey{"R1", 0}) {
			t.Errorf("unexpected fill key %+v", k)
		}
	}
	if len(uids) != 1 || !uids["R1"] {
		t.Errorf("fillUIDs = %v, want {R1}", uids)
	}
}

func TestMaxTravelAvgByRoute(t *testing.T) {
	in := map[travelAvgKey]int{
		{"R1", 0, "S1", 8, 3}: 120,
		{"R1", 0, "S2", 8, 3}: 300,
		{"R1", 0, "S3", 8, 3}: 200,
		{"R2", 1, "S1", 8, 3}: 90,
	}
	got := maxTravelAvgByRoute(in)
	if got[routeDirKey{"R1", 0}] != 300 {
		t.Errorf("R1/0 max = %d, want 300", got[routeDirKey{"R1", 0}])
	}
	if got[routeDirKey{"R2", 1}] != 90 {
		t.Errorf("R2/1 max = %d, want 90", got[routeDirKey{"R2", 1}])
	}
}

func TestBuildUpstreamObs(t *testing.T) {
	now := time.Date(2026, 7, 10, 8, 0, 0, 0, time.UTC)
	// baselineFor stub: S1 has a baseline 100s ahead of now; S9 has none (zero).
	baselineFor := func(b busStationmap, uid string, dir int32) time.Time {
		if b.StopUID == "S1" {
			return now.Add(100 * time.Second)
		}
		return time.Time{}
	}
	mp := []busStationmap{
		{SubRouteUID: "R1", Direction: 0, StopUID: "S1", StopSequence: 3}, // en route, has baseline → obs
		{SubRouteUID: "R1", Direction: 0, StopUID: "S9", StopSequence: 5}, // en route, zero baseline → skip
		{SubRouteUID: "R1", Direction: 0, StopUID: "S2", StopSequence: 4}, // status 1 → skip
	}
	etamap := map[etaKey]rawBusEsimated{
		{"R1", 0, "S1"}: {StopStatus: 0, EstimatedTime: 160}, // observed arrival now+160
		{"R1", 0, "S9"}: {StopStatus: 0, EstimatedTime: 60},
		{"R1", 0, "S2"}: {StopStatus: 1},
	}
	got := buildUpstreamObs("Taipei", mp, etamap, now, baselineFor)
	obs := got[routeDirKey{"R1", 0}]
	if len(obs) != 1 {
		t.Fatalf("obs count = %d, want 1", len(obs))
	}
	// delay = observedArrival(now+160) - baseline(now+100) = 60s late.
	if obs[0].stopSequence != 3 || obs[0].delaySeconds != 60 {
		t.Errorf("obs = %+v, want seq 3 delay 60", obs[0])
	}
}

func TestNearestBus(t *testing.T) {
	stopLat, stopLon := 25.0400, 121.5300
	buses := []*models.BusPosition{
		{PlateNumb: "FAR-1", PositionLat: 25.1000, PositionLon: 121.6000, Speed: 30},
		{PlateNumb: "NEAR-1", PositionLat: 25.0405, PositionLon: 121.5305, Speed: 12},
	}

	t.Run("picks nearest vehicle", func(t *testing.T) {
		plate, speed, dist := nearestBus(stopLat, stopLon, buses)
		if plate == nil || *plate != "NEAR-1" {
			t.Fatalf("plate = %v, want NEAR-1", plate)
		}
		if speed == nil || *speed != 12 {
			t.Errorf("speed = %v, want 12", speed)
		}
		if dist == nil || *dist <= 0 {
			t.Errorf("dist = %v, want positive metres", dist)
		}
	})

	t.Run("no buses returns nil", func(t *testing.T) {
		plate, speed, dist := nearestBus(stopLat, stopLon, nil)
		if plate != nil || speed != nil || dist != nil {
			t.Errorf("want all nil, got %v %v %v", plate, speed, dist)
		}
	})

	t.Run("stop without coordinate returns nil", func(t *testing.T) {
		plate, speed, dist := nearestBus(0, stopLon, buses)
		if plate != nil || speed != nil || dist != nil {
			t.Errorf("want all nil for lat==0, got %v %v %v", plate, speed, dist)
		}
	})
}

func TestComputeArrivalUnix(t *testing.T) {
	now := time.Date(2026, 7, 10, 8, 0, 0, 0, time.UTC)
	tests := []struct {
		name        string
		status      uint8
		est         int32
		nextBusTime string
		want        int64
	}{
		{"status 0 positive estimate", 0, 90, "", now.Add(90 * time.Second).Unix()},
		{"status 0 non-positive estimate stays zero", 0, 0, "", 0},
		{"status 1 valid next bus time", 1, 0, "2026-07-10T08:05:00Z", time.Date(2026, 7, 10, 8, 5, 0, 0, time.UTC).Unix()},
		{"status 1 empty next bus time stays zero", 1, 0, "", 0},
		{"status 1 unparseable next bus time stays zero", 1, 0, "not-a-time", 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := computeArrivalUnix(tt.status, tt.est, tt.nextBusTime, now); got != tt.want {
				t.Fatalf("computeArrivalUnix() = %d, want %d", got, tt.want)
			}
		})
	}
}
