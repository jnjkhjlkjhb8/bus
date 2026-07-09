package main

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
)

// copyUpsertCall records one captured copyUpsert invocation so a test can assert
// on the target temp table, columns, and staged rows without a database.
type copyUpsertCall struct {
	spec copyUpsertSpec
	rows [][]any
}

// fakeLoadSink is the loadSink seam's in-memory adapter: it captures every
// copyUpsert call and exposes a nil pool/redis, so the migrated copy-upsert
// transforms run end to end from JSON fixtures with no DATABASE_URL.
type fakeLoadSink struct {
	calls []copyUpsertCall
}

func (f *fakeLoadSink) copyUpsert(_ context.Context, spec copyUpsertSpec, rows [][]any) error {
	f.calls = append(f.calls, copyUpsertCall{spec: spec, rows: rows})
	return nil
}

func (f *fakeLoadSink) pool() *pgxpool.Pool  { return nil }
func (f *fakeLoadSink) redis() *redis.Client { return nil }

// decodeInto returns a decoder positioned at the start of a committed JSON array.
func decodeInto(body string) *json.Decoder {
	return json.NewDecoder(bytes.NewReader([]byte(body)))
}

func TestLoadMrtStationsThroughSink(t *testing.T) {
	body := `[{"StationID":"BL12","StationName":{"Zh_tw":"南港展覽館"},"LocationCity":"Taipei","StationPosition":{"PositionLon":121.6,"PositionLat":25.05},"BikeAllowOnHoliday":true}]`
	sink := &fakeLoadSink{}
	if err := loadMrtStations(context.Background(), decodeInto(body), sink, "TRTC"); err != nil {
		t.Fatalf("loadMrtStations: %v", err)
	}
	if len(sink.calls) != 1 {
		t.Fatalf("copyUpsert calls = %d, want 1", len(sink.calls))
	}
	c := sink.calls[0]
	if c.spec.key != "mrt_station" || c.spec.tempTable != "temp_mrt" {
		t.Fatalf("spec key/temp = %q/%q", c.spec.key, c.spec.tempTable)
	}
	wantCols := []string{"geom", "system", "name", "city", "id", "bike"}
	if !equalStrings(c.spec.copyCols, wantCols) {
		t.Fatalf("copyCols = %v, want %v", c.spec.copyCols, wantCols)
	}
	if len(c.rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(c.rows))
	}
	want := []any{"POINT(121.600000 25.050000)", "TRTC", "南港展覽館", "Taipei", "BL12", true}
	for i, v := range want {
		if c.rows[0][i] != v {
			t.Fatalf("row[%d] = %#v, want %#v", i, c.rows[0][i], v)
		}
	}
}

func TestLoadTraTimetableThroughSink(t *testing.T) {
	// WheelchairFlag (bit 0) + DiningFlag (bit 2) set ⇒ railMask = 1|4 = 5. The
	// service-day mask stays in the transform's row mapping, not the sink helper.
	body := `[{"DailyTrainInfo":{"TrainNo":"123","Direction":0,"WheelchairFlag":1,"DiningFlag":1},"StopTimes":[{"StopSequence":1,"StationID":"1000","StationName":{"Zh_tw":"台北"},"ArrivalTime":"08:00","DepartureTime":"08:01"}]}]`
	sink := &fakeLoadSink{}
	if err := loadTraTimetable(context.Background(), decodeInto(body), sink, "2026-07-04"); err != nil {
		t.Fatalf("loadTraTimetable: %v", err)
	}
	if len(sink.calls) != 1 {
		t.Fatalf("copyUpsert calls = %d, want 1", len(sink.calls))
	}
	c := sink.calls[0]
	if c.spec.key != "tra_timetable" || c.spec.tempTable != "temp_tra_timetable" {
		t.Fatalf("spec key/temp = %q/%q", c.spec.key, c.spec.tempTable)
	}
	if len(c.rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(c.rows))
	}
	// mask is column index 16 in the temp_tra_timetable row layout.
	if got, ok := c.rows[0][16].(uint16); !ok || got != 5 {
		t.Fatalf("mask = %#v, want uint16(5)", c.rows[0][16])
	}
	if c.rows[0][0] != "2026-07-04" || c.rows[0][12] != "1000" {
		t.Fatalf("row train_date/stationid = %v/%v", c.rows[0][0], c.rows[0][12])
	}
}

func TestLoadThsrTimetableThroughSink(t *testing.T) {
	// Overnight handling stays in the THSR row mapping; assert it survives to the
	// staged row (column index 13 in the temp_thsr_timetable layout).
	body := `[{"TrainDate":"2026-07-04","DailyTrainInfo":{"TrainNo":"0101","Direction":1,"Overnight":true},"StopTimes":[{"StopSequence":1,"StationID":"0990","StationName":{"Zh_tw":"南港"},"ArrivalTime":"23:50","DepartureTime":"23:51"}]}]`
	sink := &fakeLoadSink{}
	if err := loadThsrTimetable(context.Background(), decodeInto(body), sink, "2026-07-04"); err != nil {
		t.Fatalf("loadThsrTimetable: %v", err)
	}
	if len(sink.calls) != 1 {
		t.Fatalf("copyUpsert calls = %d, want 1", len(sink.calls))
	}
	c := sink.calls[0]
	if c.spec.key != "thsr_timetable" || c.spec.tempTable != "temp_thsr_timetable" {
		t.Fatalf("spec key/temp = %q/%q", c.spec.key, c.spec.tempTable)
	}
	if len(c.rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(c.rows))
	}
	if got, ok := c.rows[0][13].(bool); !ok || !got {
		t.Fatalf("overnight = %#v, want true", c.rows[0][13])
	}
}

// TestLoadMrtStationsEmptyNoCall proves an empty payload short-circuits before
// touching the sink (no partition write on zero rows), matching the transform's
// len==0 guard.
func TestLoadMrtStationsEmptyNoCall(t *testing.T) {
	sink := &fakeLoadSink{}
	if err := loadMrtStations(context.Background(), decodeInto(`[]`), sink, "TRTC"); err != nil {
		t.Fatalf("loadMrtStations: %v", err)
	}
	if len(sink.calls) != 0 {
		t.Fatalf("copyUpsert calls = %d, want 0 for empty payload", len(sink.calls))
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
