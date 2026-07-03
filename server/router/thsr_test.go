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
