package main

import (
	"context"
	"strings"
	"testing"
)

func TestLoadBikeStationsRejectsMalformedElement(t *testing.T) {
	sink := &fakeLoadSink{}
	err := loadBikeStations(context.Background(), decodeInto(`[
		{"StationUID":"TPE001","StationID":"001","StationPosition":{"PositionLon":121.5,"PositionLat":25.0},"ServiceType":2},
		{"StationUID":
	]`), sink, "Taipei")
	if err == nil || !strings.Contains(err.Error(), "element 1") {
		t.Fatalf("loadBikeStations error = %v, want wrapped element 1 decode error", err)
	}
	if len(sink.calls) != 0 {
		t.Fatalf("copyUpsert calls = %d, want no write for malformed payload", len(sink.calls))
	}
}

func TestLoadBikeStationsRejectsInvalidIdentityOrPosition(t *testing.T) {
	tests := []struct {
		name string
		body string
		want string
	}{
		{
			name: "missing station uid",
			body: `[{"StationID":"001","StationPosition":{"PositionLon":121.5,"PositionLat":25.0},"ServiceType":2}]`,
			want: "StationUID",
		},
		{
			name: "zero position",
			body: `[{"StationUID":"TPE001","StationID":"001","StationPosition":{"PositionLon":0,"PositionLat":0},"ServiceType":2}]`,
			want: "position",
		},
		{
			name: "unknown service type",
			body: `[{"StationUID":"TPE001","StationID":"001","StationPosition":{"PositionLon":121.5,"PositionLat":25.0},"ServiceType":3}]`,
			want: "ServiceType",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			err := loadBikeStations(context.Background(), decodeInto(tt.body), sink, "Taipei")
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("loadBikeStations error = %v, want %q validation error", err, tt.want)
			}
			if len(sink.calls) != 0 {
				t.Fatalf("copyUpsert calls = %d, want no write for invalid station", len(sink.calls))
			}
		})
	}
}

func TestLoadBikeStationsDuplicatePolicy(t *testing.T) {
	station := `{"StationUID":"TPE001","StationID":"001","StationPosition":{"PositionLon":121.5,"PositionLat":25.0},"ServiceType":2}`
	t.Run("identical dedupe", func(t *testing.T) {
		sink := &fakeLoadSink{}
		if err := loadBikeStations(context.Background(), decodeInto(`[`+station+`,`+station+`]`), sink, "Taipei"); err != nil {
			t.Fatalf("loadBikeStations: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("rows = %+v, want one deduped station", sink.calls)
		}
	})
	t.Run("divergent reject", func(t *testing.T) {
		sink := &fakeLoadSink{}
		other := `{"StationUID":"TPE001","StationID":"001","StationPosition":{"PositionLon":121.6,"PositionLat":25.0},"ServiceType":2}`
		err := loadBikeStations(context.Background(), decodeInto(`[`+station+`,`+other+`]`), sink, "Taipei")
		if err == nil || !strings.Contains(err.Error(), "duplicate StationUID") {
			t.Fatalf("loadBikeStations error = %v, want divergent duplicate error", err)
		}
		if len(sink.calls) != 0 {
			t.Fatal("divergent duplicate reached sink")
		}
	})
}
