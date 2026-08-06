package main

import (
	"context"
	"errors"
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

func TestDataTaipeiRawPositions(t *testing.T) {
	buses := []dataTaipeiBus{
		{
			BusID: "757-FW", RouteID: "11202", GoBack: "1",
			Longitude: "121.500962", Latitude: "25.090732",
			Speed: "23", Azimuth: "314", DutyStatus: "2", BusStatus: "0",
			DataTime: "2026-08-06 11:20:40",
		},
		// Direction 未知: no canonical subroute can be derived, so it is dropped.
		{BusID: "730-FW", RouteID: "10283", GoBack: "2", Longitude: "121.5", Latitude: "25.0"},
		// Unplaceable coordinate: dropped rather than published at (0, 0).
		{BusID: "001-AA", RouteID: "10283", GoBack: "0", Longitude: "", Latitude: ""},
	}
	events := []dataTaipeiEvent{
		{BusID: "757-FW", StopID: "18620", CarOnStop: "1"},
		// Already pulled out of the stop: carries no location.
		{BusID: "999-ZZ", StopID: "18621", CarOnStop: "0"},
	}

	seats := []dataTaipeiSeat{
		{BusID: "757-FW", Level: intPtr(2)},
		// A null reading stays missing rather than decoding to 0 (舒適).
		{BusID: "730-FW", Level: nil},
	}

	got := dataTaipeiRawPositions(buses, events, seats)

	if len(got) != 1 {
		t.Fatalf("positions = %d rows, want 1: %+v", len(got), got)
	}
	p := got[0]
	if p.SubRouteUID != "TPE11202" {
		t.Errorf("SubRouteUID = %q, want TPE11202", p.SubRouteUID)
	}
	if p.StopUID != "TPE18620" {
		t.Errorf("StopUID = %q, want TPE18620", p.StopUID)
	}
	if p.PlateNumb != "757-FW" {
		t.Errorf("PlateNumb = %q, want 757-FW", p.PlateNumb)
	}
	if p.Direction != 1 {
		t.Errorf("Direction = %d, want 1", p.Direction)
	}
	if p.BusPosition.PositionLon != 121.500962 || p.BusPosition.PositionLat != 25.090732 {
		t.Errorf("position = (%v, %v), want (121.500962, 25.090732)",
			p.BusPosition.PositionLon, p.BusPosition.PositionLat)
	}
	if p.Speed != 23 || p.Azimuth != 314 {
		t.Errorf("speed/azimuth = %v/%v, want 23/314", p.Speed, p.Azimuth)
	}
	if p.DutyStatus != 2 || p.BusStatus != 0 {
		t.Errorf("duty/bus status = %d/%d, want 2/0", p.DutyStatus, p.BusStatus)
	}
	if parseGPSTimeUnix(p.GPSTime) == 0 {
		t.Errorf("GPSTime %q does not parse", p.GPSTime)
	}
	if p.CrowdLevel != models.BusCrowdLevel_BUS_CROWD_CROWDED {
		t.Errorf("CrowdLevel = %v, want CROWDED", p.CrowdLevel)
	}
}

func intPtr(v int) *int { return &v }

func TestDataTaipeiCrowdLevel(t *testing.T) {
	tests := []struct {
		name  string
		level *int
		want  models.BusCrowdLevel
		ok    bool
	}{
		{"comfortable", intPtr(0), models.BusCrowdLevel_BUS_CROWD_COMFORTABLE, true},
		{"normal", intPtr(1), models.BusCrowdLevel_BUS_CROWD_NORMAL, true},
		{"crowded", intPtr(2), models.BusCrowdLevel_BUS_CROWD_CROWDED, true},
		// 33 of 1,541 vehicles publish null; an undocumented band is the same
		// situation — a reading we cannot label.
		{"null reading", nil, models.BusCrowdLevel_BUS_CROWD_UNKNOWN, false},
		{"undocumented band", intPtr(9), models.BusCrowdLevel_BUS_CROWD_UNKNOWN, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := dataTaipeiCrowdLevel(tt.level)
			if got != tt.want || ok != tt.ok {
				t.Errorf("dataTaipeiCrowdLevel() = %v, %v; want %v, %v", got, ok, tt.want, tt.ok)
			}
		})
	}
}

func TestMergeDataTaipeiPositions(t *testing.T) {
	tdx := []rawBusPosition{
		{SubRouteUID: "TPE11202", Direction: 1, PlateNumb: ""},
		{SubRouteUID: "TPE11202", Direction: 0, PlateNumb: ""},
		{SubRouteUID: "TPE99999", Direction: 0, PlateNumb: ""},
	}
	fresh := []rawBusPosition{
		{SubRouteUID: "TPE11202", Direction: 1, PlateNumb: "757-FW"},
	}

	got := mergeDataTaipeiPositions(tdx, fresh)

	// The covered direction comes from Data.taipei alone; the other direction and
	// the subroute it never reported keep their TDX rows.
	if len(got) != 3 {
		t.Fatalf("merged = %d rows, want 3: %+v", len(got), got)
	}
	for _, p := range got {
		if p.SubRouteUID == "TPE11202" && p.Direction == 1 && p.PlateNumb != "757-FW" {
			t.Errorf("TDX row survived for a covered subroute direction: %+v", p)
		}
	}
}

func TestMergeDataTaipeiPositionsEmptyKeepsTDX(t *testing.T) {
	tdx := []rawBusPosition{{SubRouteUID: "TPE11202", Direction: 1}}
	if got := mergeDataTaipeiPositions(tdx, nil); len(got) != 1 {
		t.Fatalf("merged = %d rows, want the 1 TDX row back", len(got))
	}
}

func TestGunzipIfCompressed(t *testing.T) {
	plain := []byte(`{"BusInfo":[]}`)
	got, err := gunzipIfCompressed(plain)
	if err != nil || string(got) != string(plain) {
		t.Fatalf("uncompressed body = %q, %v; want it back unchanged", got, err)
	}
}

func TestBuildBusAtStopMap(t *testing.T) {
	positions := []rawBusPosition{
		{SubRouteUID: "TPE11202", Direction: 1, StopUID: "TPE18620", PlateNumb: "757-FW", Speed: 12},
		// No stop event for this vehicle: it stays out of the index entirely, so
		// its stop keeps whatever nearestBus guessed.
		{SubRouteUID: "TPE11202", Direction: 1, StopUID: "", PlateNumb: "730-FW"},
	}

	index := buildBusAtStopMap("Taipei", positions)

	plate, speed, dist, ok := busAtStop(index, busAtStopKey{"TPE11202", 1, "TPE18620"})
	if !ok {
		t.Fatalf("stop with a reported vehicle resolved nothing")
	}
	if *plate != "757-FW" || *speed != 12 || *dist != 0 {
		t.Errorf("at-stop bus = %q/%d/%d, want 757-FW/12/0", *plate, *speed, *dist)
	}
	if _, _, _, ok := busAtStop(index, busAtStopKey{"TPE11202", 1, "TPE99999"}); ok {
		t.Errorf("stop with no reported vehicle resolved one")
	}
}

func TestBuildBusAtStopMapIgnoresTDXPositions(t *testing.T) {
	// TDX positions never carry a StopUID, so every other city keeps nearestBus.
	positions := []rawBusPosition{{SubRouteUID: "TXG1234", Direction: 0, PlateNumb: "ABC-123"}}
	if index := buildBusAtStopMap("Taichung", positions); len(index) != 0 {
		t.Fatalf("index = %d entries, want 0", len(index))
	}
}

// stubVehicleSource stands in for the blob feed so the overlay can be exercised
// without a network call.
type stubVehicleSource struct {
	rows []rawBusPosition
	err  error
}

func (s stubVehicleSource) positions(context.Context) ([]rawBusPosition, error) {
	return s.rows, s.err
}

func TestOverlayVehicles(t *testing.T) {
	tdx := []rawBusPosition{{SubRouteUID: "TPE11202", Direction: 1}}
	fresh := []rawBusPosition{{SubRouteUID: "TPE11202", Direction: 1, PlateNumb: "757-FW"}}

	tests := []struct {
		name      string
		job       busLiveJob
		city      string
		wantPlate string
	}{
		{
			name:      "covered city takes the richer feed",
			job:       busLiveJob{vehicles: stubVehicleSource{rows: fresh}},
			city:      dataTaipeiCity,
			wantPlate: "757-FW",
		},
		{
			name: "other cities are untouched",
			job:  busLiveJob{vehicles: stubVehicleSource{rows: fresh}},
			city: "Taichung",
		},
		{
			name: "a failing feed falls back to TDX",
			job:  busLiveJob{vehicles: stubVehicleSource{err: errors.New("blob unreachable")}},
			city: dataTaipeiCity,
		},
		{
			name: "no feed configured stays on TDX",
			job:  busLiveJob{},
			city: dataTaipeiCity,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.job.overlayVehicles(context.Background(), tt.city, tdx)
			if len(got) != 1 {
				t.Fatalf("positions = %d rows, want 1", len(got))
			}
			if got[0].PlateNumb != tt.wantPlate {
				t.Errorf("PlateNumb = %q, want %q", got[0].PlateNumb, tt.wantPlate)
			}
		})
	}
}
