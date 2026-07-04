package main

import (
	"context"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/pashagolub/pgxmock/v4"
	"google.golang.org/protobuf/proto"
)

// TestTraFarePayloadReturnsRows verifies the read path marshals matching fares.
func TestTraFarePayloadReturnsRows(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type,price FROM tra_fares").
		WithArgs("1000", "1040").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "price"}).AddRow("成人", int32(41)))

	payload, err := traFarePayload(context.Background(), db, "1000", "1040")
	if err != nil {
		t.Fatal(err)
	}
	var fares models.TraFareItems
	if err := proto.Unmarshal(payload, &fares); err != nil {
		t.Fatal(err)
	}
	if len(fares.Items) != 1 || fares.Items[0].Price != 41 || fares.Items[0].TicketType != "成人" {
		t.Fatalf("fares = %+v, want one fare priced 41", fares.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraFarePayloadEmptyOnNoRows verifies an unlanded date yields an empty
// payload (nil bytes) so the handler maps it to NotFound (ADR-0005).
func TestTraFarePayloadEmptyOnNoRows(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type,price FROM tra_fares").
		WithArgs("1000", "1040").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "price"}))

	payload, err := traFarePayload(context.Background(), db, "1000", "1040")
	if err != nil {
		t.Fatal(err)
	}
	if len(payload) != 0 {
		t.Fatalf("want empty payload, got %d bytes", len(payload))
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraStoptimesPayloadSetsSuspendedFromMask verifies the suspended bit (mask
// bit 7) is decoded onto the proto and the row count is reported.
func TestTraStoptimesPayloadSetsSuspendedFromMask(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("FROM tra_timetable WHERE trainno").
		WithArgs("1234", "2026-07-04").
		WillReturnRows(pgxmock.NewRows([]string{"stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask"}).
			AddRow(1, "1000", "台北", "08:00", "08:02", int32(1<<7)))

	payload, n, err := traStoptimesPayload(context.Background(), db, "1234", "2026-07-04")
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("row count = %d, want 1", n)
	}
	var stops models.TraStoptimes
	if err := proto.Unmarshal(payload, &stops); err != nil {
		t.Fatal(err)
	}
	if len(stops.Items) != 1 || !stops.Items[0].SuspendedFlag {
		t.Fatalf("stops = %+v, want one suspended stop", stops.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraStoptimesPayloadEmptyOnNoRows verifies a zero count on an empty table.
func TestTraStoptimesPayloadEmptyOnNoRows(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("FROM tra_timetable WHERE trainno").
		WithArgs("1234", "2026-07-04").
		WillReturnRows(pgxmock.NewRows([]string{"stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask"}))

	_, n, err := traStoptimesPayload(context.Background(), db, "1234", "2026-07-04")
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("row count = %d, want 0", n)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraTimetablePayloadPairsOriginDestination verifies origin/destination legs
// are paired into a single timetable entry with a computed travel time.
func TestTraTimetablePayloadPairsOriginDestination(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	date := time.Date(2026, 7, 4, 0, 0, 0, 0, time.UTC)
	originArr := time.Date(2026, 7, 4, 8, 0, 0, 0, time.UTC)
	destArr := time.Date(2026, 7, 4, 9, 0, 0, 0, time.UTC)
	cols := []string{
		"train_date", "trainno", "starting_station_id", "starting_station_name",
		"ending_station_id", "ending_station_name", "stopsequence", "train_type_id",
		"train_type_code", "train_type_name", "tripline", "stationid", "arrivaltime",
		"stationname", "mask", "note", "departuretime",
	}
	db.ExpectQuery("FROM tra_timetable WHERE stationid = ANY").
		WithArgs([]string{"1000", "1040"}, "2026-07-04", date.Format(time.TimeOnly)).
		WillReturnRows(pgxmock.NewRows(cols).
			AddRow(date, "1234", "1000", "台北", "1040", "台中", 1, "1", "1", "自強", int32(0), "1000", originArr, "台北", int32(0), "", originArr).
			AddRow(date, "1234", "1000", "台北", "1040", "台中", 5, "1", "1", "自強", int32(0), "1040", destArr, "台中", int32(0), "", destArr))

	payload, n, err := traTimetablePayload(context.Background(), db, "1000", "1040", date)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("leg count = %d, want 1", n)
	}
	var tt models.TraTimetables
	if err := proto.Unmarshal(payload, &tt); err != nil {
		t.Fatal(err)
	}
	if len(tt.Items) != 1 || tt.Items[0].TrainNo != "1234" || tt.Items[0].Travel_Time != "1h0m0s" {
		t.Fatalf("timetable = %+v, want one leg with 1h travel", tt.Items)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
