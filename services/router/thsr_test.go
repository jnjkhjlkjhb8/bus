package main

import (
	"context"
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/pashagolub/pgxmock/v4"
	"google.golang.org/protobuf/proto"
)

func TestThsrFarePayloadSkipsRefreshWhenDBHasRows(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}).AddRow(uint8(1), uint8(2), uint8(3), int32(120)))

	refreshed := 0
	payload, err := thsrFarePayload(context.Background(), "0990", "1000", db, func() { refreshed++ })
	if err != nil {
		t.Fatal(err)
	}
	if refreshed != 0 {
		t.Fatalf("refresh count = %d, want 0", refreshed)
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

// TestThsrFarePayloadNilRefreshOnEmpty covers the read path (ADR-0005): with a
// nil refresh the helper returns an empty payload on an empty DB instead of
// fetching from TDX, so the handler can map it to NotFound.
func TestThsrFarePayloadNilRefreshOnEmpty(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}))

	payload, err := thsrFarePayload(context.Background(), "0990", "1000", db, nil)
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

func TestThsrFarePayloadRefreshesOnlyWhenDBIsEmpty(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}))
	db.ExpectQuery("SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares").
		WithArgs("0990", "1000").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "fare_class", "cabin_class", "price"}).AddRow(uint8(1), uint8(2), uint8(3), int32(120)))

	refreshed := 0
	payload, err := thsrFarePayload(context.Background(), "0990", "1000", db, func() { refreshed++ })
	if err != nil {
		t.Fatal(err)
	}
	if refreshed != 1 {
		t.Fatalf("refresh count = %d, want 1", refreshed)
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
