package main

import (
	"context"
	"strings"
	"testing"
)

func TestLoadThsrStationRejectsMalformedElement(t *testing.T) {
	err := loadThsrStation(context.Background(), decodeInto(`[
		{"StationID":"0990","StationCode":"NAK","LocationCityCode":"TPE","StationPosition":{"PositionLon":121.6,"PositionLat":25.05}},
		{"StationID":
	]`), &fakeLoadSink{}, "")
	if err == nil || !strings.Contains(err.Error(), "element 1") {
		t.Fatalf("loadThsrStation error = %v, want wrapped element 1 decode error", err)
	}
}

func TestLoadRailTimetablesRejectInvalidTimeDateIdentityOrFlag(t *testing.T) {
	tests := []struct {
		name string
		load func(context.Context, *fakeLoadSink, string) error
		want string
	}{
		{
			name: "TRA invalid partition date",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadTraTimetable(ctx, decodeInto(`[]`), sink, "2026-02-30")
			},
			want: "date",
		},
		{
			name: "TRA missing train identity",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadTraTimetable(ctx, decodeInto(`[{"DailyTrainInfo":{"StartingStationID":"1000","EndingStationID":"1001"},"StopTimes":[{"StopSequence":1,"StationID":"1000","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]`), sink, "2026-07-15")
			},
			want: "TrainNo",
		},
		{
			name: "TRA invalid clock",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadTraTimetable(ctx, decodeInto(`[{"DailyTrainInfo":{"TrainNo":"123","StartingStationID":"1000","EndingStationID":"1001"},"StopTimes":[{"StopSequence":1,"StationID":"1000","ArrivalTime":"25:00","DepartureTime":"08:01"}]}]`), sink, "2026-07-15")
			},
			want: "ArrivalTime",
		},
		{
			name: "TRA invalid boolean flag",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadTraTimetable(ctx, decodeInto(`[{"DailyTrainInfo":{"TrainNo":"123","StartingStationID":"1000","EndingStationID":"1001","WheelchairFlag":2},"StopTimes":[{"StopSequence":1,"StationID":"1000","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]`), sink, "2026-07-15")
			},
			want: "WheelchairFlag",
		},
		{
			name: "THSR mismatched train date",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadThsrTimetable(ctx, decodeInto(`[{"TrainDate":"2026-07-16","DailyTrainInfo":{"TrainNo":"0101","StartingStationID":"0990","EndingStationID":"1070"},"StopTimes":[{"StopSequence":1,"StationID":"0990","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]`), sink, "2026-07-15")
			},
			want: "TrainDate",
		},
		{
			name: "THSR missing stop identity",
			load: func(ctx context.Context, sink *fakeLoadSink, _ string) error {
				return loadThsrTimetable(ctx, decodeInto(`[{"TrainDate":"2026-07-15","DailyTrainInfo":{"TrainNo":"0101","StartingStationID":"0990","EndingStationID":"1070"},"StopTimes":[{"StopSequence":1,"ArrivalTime":"08:00","DepartureTime":"08:01"}]}]`), sink, "2026-07-15")
			},
			want: "StationID",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			err := tt.load(context.Background(), sink, tt.name)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("load error = %v, want %q", err, tt.want)
			}
			if len(sink.calls) != 0 {
				t.Fatalf("copyUpsert calls = %d, want no write", len(sink.calls))
			}
		})
	}
}

func TestLoadRailTimetableValidEmptyReplacesDate(t *testing.T) {
	for _, tt := range []struct {
		name string
		load func(context.Context, *fakeLoadSink) error
	}{
		{"TRA", func(ctx context.Context, sink *fakeLoadSink) error {
			return loadTraTimetable(ctx, decodeInto(`[]`), sink, "2026-07-15")
		}},
		{"THSR", func(ctx context.Context, sink *fakeLoadSink) error {
			return loadThsrTimetable(ctx, decodeInto(`[]`), sink, "2026-07-15")
		}},
	} {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			if err := tt.load(context.Background(), sink); err != nil {
				t.Fatalf("load: %v", err)
			}
			if len(sink.calls) != 1 || len(sink.calls[0].rows) != 0 || len(sink.calls[0].spec.preExec) != 1 {
				t.Fatalf("calls = %+v, want one zero-row date replacement", sink.calls)
			}
		})
	}
}

func TestLoadRailStationsRejectInvalidIdentityCityOrPosition(t *testing.T) {
	tests := []struct {
		name string
		load func(context.Context, *fakeLoadSink) error
		want string
	}{
		{
			name: "TRA missing station ID",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadTraStation(ctx, decodeInto(`[{"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.5,"PositionLat":25.0}}]`), sink, "")
			},
			want: "StationID",
		},
		{
			name: "TRA unknown city",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadTraStation(ctx, decodeInto(`[{"StationID":"1000","LocationCityCode":"ZZZ","StationPosition":{"PositionLon":121.5,"PositionLat":25.0}}]`), sink, "")
			},
			want: "LocationCityCode",
		},
		{
			name: "THSR invalid position",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadThsrStation(ctx, decodeInto(`[{"StationID":"0990","StationCode":"NAK","LocationCityCode":"TPE","StationPosition":{"PositionLon":0,"PositionLat":0}}]`), sink, "")
			},
			want: "position",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			err := tt.load(context.Background(), sink)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("load error = %v, want %q", err, tt.want)
			}
			if len(sink.calls) != 0 {
				t.Fatalf("copyUpsert calls = %d, want no write", len(sink.calls))
			}
		})
	}
}

func TestLoadRailFaresRejectInvalidIdentity(t *testing.T) {
	tests := []struct {
		name string
		load func(context.Context, *fakeLoadSink) error
		want string
	}{
		{
			name: "TRA missing origin",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadTraFare(ctx, decodeInto(`[{"DestinationStationID":"1001","Fares":[{"TicketType":"Adult","Price":40}]}]`), sink, "")
			},
			want: "OriginStationID",
		},
		{
			name: "TRA missing ticket type",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadTraFare(ctx, decodeInto(`[{"OriginStationID":"1000","DestinationStationID":"1001","Fares":[{"Price":40}]}]`), sink, "")
			},
			want: "TicketType",
		},
		{
			name: "THSR missing destination",
			load: func(ctx context.Context, sink *fakeLoadSink) error {
				return loadThsrFare(ctx, decodeInto(`[{"OriginStationID":"0990","Fares":[{"TicketType":1,"FareClass":1,"CabinClass":1,"Price":40}]}]`), sink, "")
			},
			want: "DestinationStationID",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			err := tt.load(context.Background(), sink)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("load error = %v, want %q", err, tt.want)
			}
			if len(sink.calls) != 0 {
				t.Fatalf("copyUpsert calls = %d, want no write", len(sink.calls))
			}
		})
	}
}

func TestLoadRailFareValidEmptyIsNoOp(t *testing.T) {
	for _, tt := range []struct {
		name string
		load func(context.Context, *fakeLoadSink) error
	}{
		{"TRA", func(ctx context.Context, sink *fakeLoadSink) error {
			return loadTraFare(ctx, decodeInto(`[]`), sink, "")
		}},
		{"THSR", func(ctx context.Context, sink *fakeLoadSink) error {
			return loadThsrFare(ctx, decodeInto(`[]`), sink, "")
		}},
	} {
		t.Run(tt.name, func(t *testing.T) {
			sink := &fakeLoadSink{}
			if err := tt.load(context.Background(), sink); err != nil {
				t.Fatalf("load: %v", err)
			}
			if len(sink.calls) != 0 {
				t.Fatalf("copyUpsert calls = %d, want additive empty no-op", len(sink.calls))
			}
		})
	}
}

func TestLoadRailDuplicatePolicies(t *testing.T) {
	t.Run("TRA station identical dedupe and divergent reject", func(t *testing.T) {
		station := `{"StationID":"1000","StationName":{"Zh_tw":"台北"},"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.5,"PositionLat":25.0}}`
		sink := &fakeLoadSink{}
		if err := loadTraStation(context.Background(), decodeInto(`[`+station+`,`+station+`]`), sink, ""); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"StationID":"1000","StationName":{"Zh_tw":"臺北"},"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.5,"PositionLat":25.0}}`
		err := loadTraStation(context.Background(), decodeInto(`[`+station+`,`+other+`]`), &fakeLoadSink{}, "")
		if err == nil || !strings.Contains(err.Error(), "duplicate station") {
			t.Fatalf("divergent error = %v", err)
		}
	})
	t.Run("THSR station identical dedupe and divergent reject", func(t *testing.T) {
		station := `{"StationID":"0990","StationCode":"0990","StationName":{"Zh_tw":"南港"},"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.6,"PositionLat":25.05}}`
		sink := &fakeLoadSink{}
		if err := loadThsrStation(context.Background(), decodeInto(`[`+station+`,`+station+`]`), sink, ""); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"StationID":"0990","StationCode":"0990","StationName":{"Zh_tw":"南港站"},"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.6,"PositionLat":25.05}}`
		err := loadThsrStation(context.Background(), decodeInto(`[`+station+`,`+other+`]`), &fakeLoadSink{}, "")
		if err == nil || !strings.Contains(err.Error(), "duplicate station") {
			t.Fatalf("divergent error = %v", err)
		}
	})
	t.Run("TRA fare identical dedupe and divergent reject", func(t *testing.T) {
		fare := `{"OriginStationID":"1000","DestinationStationID":"1001","Fares":[{"TicketType":"Adult","Price":40},{"TicketType":"Adult","Price":40}]}`
		sink := &fakeLoadSink{}
		if err := loadTraFare(context.Background(), decodeInto(`[`+fare+`]`), sink, ""); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"OriginStationID":"1000","DestinationStationID":"1001","Fares":[{"TicketType":"Adult","Price":41}]}`
		err := loadTraFare(context.Background(), decodeInto(`[`+fare+`,`+other+`]`), &fakeLoadSink{}, "")
		if err == nil || !strings.Contains(err.Error(), "duplicate fare") {
			t.Fatalf("divergent error = %v", err)
		}
	})
	t.Run("THSR fare identical dedupe and divergent reject", func(t *testing.T) {
		fare := `{"OriginStationID":"0990","DestinationStationID":"1070","Fares":[{"TicketType":1,"FareClass":1,"CabinClass":1,"Price":40},{"TicketType":1,"FareClass":1,"CabinClass":1,"Price":40}]}`
		sink := &fakeLoadSink{}
		if err := loadThsrFare(context.Background(), decodeInto(`[`+fare+`]`), sink, ""); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"OriginStationID":"0990","DestinationStationID":"1070","Fares":[{"TicketType":1,"FareClass":1,"CabinClass":1,"Price":41}]}`
		err := loadThsrFare(context.Background(), decodeInto(`[`+fare+`,`+other+`]`), &fakeLoadSink{}, "")
		if err == nil || !strings.Contains(err.Error(), "duplicate fare") {
			t.Fatalf("divergent error = %v", err)
		}
	})
	t.Run("TRA timetable identical dedupe and divergent reject", func(t *testing.T) {
		row := `{"DailyTrainInfo":{"TrainNo":"123","StartingStationID":"1000","EndingStationID":"1001"},"StopTimes":[{"StopSequence":1,"StationID":"1000","ArrivalTime":"08:00","DepartureTime":"08:01"}]}`
		sink := &fakeLoadSink{}
		if err := loadTraTimetable(context.Background(), decodeInto(`[`+row+`,`+row+`]`), sink, "2026-07-15"); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"DailyTrainInfo":{"TrainNo":"123","StartingStationID":"1000","EndingStationID":"1001"},"StopTimes":[{"StopSequence":1,"StationID":"1000","ArrivalTime":"08:02","DepartureTime":"08:03"}]}`
		err := loadTraTimetable(context.Background(), decodeInto(`[`+row+`,`+other+`]`), &fakeLoadSink{}, "2026-07-15")
		if err == nil || !strings.Contains(err.Error(), "duplicate timetable") {
			t.Fatalf("divergent error = %v", err)
		}
	})
	t.Run("THSR timetable identical dedupe and divergent reject", func(t *testing.T) {
		row := `{"TrainDate":"2026-07-15","DailyTrainInfo":{"TrainNo":"0101","StartingStationID":"0990","EndingStationID":"1070"},"StopTimes":[{"StopSequence":1,"StationID":"0990","ArrivalTime":"08:00","DepartureTime":"08:01"}]}`
		sink := &fakeLoadSink{}
		if err := loadThsrTimetable(context.Background(), decodeInto(`[`+row+`,`+row+`]`), sink, "2026-07-15"); err != nil {
			t.Fatalf("identical: %v", err)
		}
		if len(sink.calls) != 1 || len(sink.calls[0].rows) != 1 {
			t.Fatalf("identical rows = %+v, want one", sink.calls)
		}
		other := `{"TrainDate":"2026-07-15","DailyTrainInfo":{"TrainNo":"0101","StartingStationID":"0990","EndingStationID":"1070"},"StopTimes":[{"StopSequence":1,"StationID":"0990","ArrivalTime":"08:02","DepartureTime":"08:03"}]}`
		err := loadThsrTimetable(context.Background(), decodeInto(`[`+row+`,`+other+`]`), &fakeLoadSink{}, "2026-07-15")
		if err == nil || !strings.Contains(err.Error(), "duplicate timetable") {
			t.Fatalf("divergent error = %v", err)
		}
	})
}
