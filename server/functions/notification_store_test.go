package main

import (
	"context"
	"testing"
	"time"

	"github.com/pashagolub/pgxmock/v4"
)

func TestNotificationStoreFiltersRouteAndEnabledDevice(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery("FROM firebase_route_subscription.*s.route_type=\\$1 AND s.route_key=\\$2.*d.push_enabled").WithArgs("bus", "R1").WillReturnRows(pgxmock.NewRows([]string{"fcm_token"}).AddRow("token"))
	got, err := (notificationStore{db: db}).subscribedTokens(context.Background(), "bus", "R1")
	if err != nil || len(got) != 1 || got[0].token != "token" {
		t.Fatalf("got=%v err=%v", got, err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationStoreClaimIsAtomic(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Now()
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='sending'.*status='pending'.*expires_at>\\$2").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	claimed, err := (notificationStore{db: db}).claim(context.Background(), "r1", now)
	if err != nil || !claimed {
		t.Fatalf("claimed=%v err=%v", claimed, err)
	}
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='sending'.*status='pending'.*expires_at>\\$2").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	claimed, err = (notificationStore{db: db}).claim(context.Background(), "r1", now)
	if err != nil || claimed {
		t.Fatalf("claimed=%v err=%v", claimed, err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationStoreFiredAndInvalidToken(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Now()
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='fired'.*status='sending'").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	fired, err := (notificationStore{db: db}).fired(context.Background(), "r1", now)
	if err != nil || !fired {
		t.Fatalf("fired=%v err=%v", fired, err)
	}
	db.ExpectExec("UPDATE firebase_device SET fcm_token='',push_enabled=FALSE.*fcm_token=\\$1").WithArgs("bad").WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if err := (notificationStore{db: db}).invalidate(context.Background(), "bad"); err != nil {
		t.Fatal(err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
