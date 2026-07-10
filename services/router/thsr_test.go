package main

import (
	"context"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/pashagolub/pgxmock/v4"
	"google.golang.org/protobuf/proto"
)

// TestThsrFarePayloadReadsFare covers the read path (ADR-0005): the helper reads
// the loaded env schema and marshals the fare it finds, never fetching from TDX.
func TestThsrFarePayloadReadsFare(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}).AddRow(uint8(1), uint8(2), uint8(3), int32(120)))

	payload, err := thsrFarePayload(context.Background(), "0990", "1000", db)
	if err != nil {
		t.Fatal(err)
	}
	var fares models.ThsaFares
	if err := proto.Unmarshal(payload, &fares); err != nil {
		t.Fatal(err)
	}
	if len(fares.Items) != 1 || fares.Items[0].Price != 120 {
		t.Fatalf("fares = %+v, want one fare priced 120", fares.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestThsrFarePayloadEmptyOnEmptyDB covers the read path (ADR-0005): the helper
// returns an empty payload on an empty DB instead of fetching from TDX, so the
// handler can map it to NotFound.
func TestThsrFarePayloadEmptyOnEmptyDB(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}))

	payload, err := thsrFarePayload(context.Background(), "0990", "1000", db)
	if err != nil {
		t.Fatal(err)
	}
	var fares models.ThsaFares
	if err := proto.Unmarshal(payload, &fares); err != nil {
		t.Fatal(err)
	}
	if len(fares.Items) != 0 {
		t.Fatalf("want empty, got %+v", fares.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestThsrTimetablePayloadUsesOriginDeparture pins the origin leg to the stop's
// departure time, not its arrival. THSR O/D queries start from a terminus
// (南港/台北) where the originating train has no arrival time (stored 00:00), so
// using arrivaltime showed every train departing at 00:00 with an absurd
// duration. Numeric ids skip station-name resolution, so only the O/D query is
// expected.
func TestThsrTimetablePayloadUsesOriginDeparture(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	cols := []string{
		"trainno", "starting_station_id", "starting_station_name",
		"ending_station_id", "ending_station_name", "arrivaltime",
		"departuretime", "note", "overnight", "stationid", "stopsequence",
	}
	db.ExpectQuery("FROM thsr_timetable WHERE stationid").
		WithArgs([]string{"0990", "1070"}, "2026-07-10").
		WillReturnRows(pgxmock.NewRows(cols).
			// Southbound 0801: origin 南港 (seq 1, terminus → no arrival, departs 06:30),
			// dest 左營 (seq 12, arrives 08:00) — the leg we want.
			AddRow("0801", "0990", "南港", "1070", "左營", "00:00:00", "06:30:00", "", false, "0990", 1).
			AddRow("0801", "0990", "南港", "1070", "左營", "08:00:00", "08:02:00", "", false, "1070", 12).
			// Northbound 0802 also calls at both stations but in reverse order
			// (左營 seq 1 → 南港 seq 12); it must be dropped, not paired backwards.
			AddRow("0802", "1070", "左營", "0990", "南港", "00:00:00", "09:00:00", "", false, "1070", 1).
			AddRow("0802", "1070", "左營", "0990", "南港", "10:30:00", "10:32:00", "", false, "0990", 12))

	date := time.Date(2026, 7, 10, 0, 0, 0, 0, time.UTC)
	payload, n, err := thsrTimetablePayload(context.Background(), db, "0990", "1070", date)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("paired legs = %d, want 1", n)
	}
	var tt models.ThsrTimetables
	if err := proto.Unmarshal(payload, &tt); err != nil {
		t.Fatal(err)
	}
	if len(tt.Items) != 1 {
		t.Fatalf("items = %+v, want one", tt.Items)
	}
	got := tt.Items[0]
	if got.Starting_Time != "06:30:00" {
		t.Errorf("Starting_Time = %q, want origin departure 06:30:00", got.Starting_Time)
	}
	if got.Ending_Time != "08:00:00" {
		t.Errorf("Ending_Time = %q, want dest arrival 08:00:00", got.Ending_Time)
	}
	if got.Travel_Time != "1h30m0s" {
		t.Errorf("Travel_Time = %q, want 1h30m0s", got.Travel_Time)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestThsrStoptimesPayload verifies the read path marshals stop times and
// reports the row count so the handler can NotFound an empty result (ADR-0005).
func TestThsrStoptimesPayload(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("FROM thsr_timetable WHERE trainno").
		WithArgs("0801", "2026-07-04").
		WillReturnRows(pgxmock.NewRows([]string{"stopsequence", "stationid", "stationname", "arrivaltime", "departuretime"}).
			AddRow(1, "0990", "南港", "08:00", "08:02"))

	payload, n, err := thsrStoptimesPayload(context.Background(), db, "0801", "2026-07-04")
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("row count = %d, want 1", n)
	}
	var stops models.ThsrStoptimes
	if err := proto.Unmarshal(payload, &stops); err != nil {
		t.Fatal(err)
	}
	if len(stops.Items) != 1 || stops.Items[0].StationId != "0990" {
		t.Fatalf("stops = %+v, want one stop at 0990", stops.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
