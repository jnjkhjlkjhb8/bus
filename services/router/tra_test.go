package main

import (
	"context"
	"errors"
	"regexp"
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

func TestTraFarePayloadOrdersCheapestFareFirst(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	wantQuery := `SELECT ticket_type,price FROM tra_fares WHERE origin_station_id = $1 AND destination_station_id = $2 ORDER BY price, ticket_type;`
	db.ExpectQuery(regexp.QuoteMeta(wantQuery)).
		WithArgs("1000", "1040").
		WillReturnRows(pgxmock.NewRows([]string{"ticket_type", "price"}).
			AddRow("優待", int32(21)).
			AddRow("成人", int32(41)))

	payload, err := traFarePayload(context.Background(), db, "1000", "1040")
	if err != nil {
		t.Fatal(err)
	}
	var fares models.TraFareItems
	if err := proto.Unmarshal(payload, &fares); err != nil {
		t.Fatal(err)
	}
	if len(fares.Items) != 2 || fares.Items[0].Price != 21 {
		t.Fatalf("fares = %+v, want cheapest fare first", fares.Items)
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
		WithArgs([]string{"1000", "1040"}, "2026-07-04", "1000", date.Format(time.TimeOnly)).
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

// TestTraTimetablePayloadPairsCrossMidnightRows supplies already-selected mock
// rows and covers only Go origin/destination pairing plus duration calculation.
// pgxmock does not execute the timetable SQL predicate.
func TestTraTimetablePayloadPairsCrossMidnightRows(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	date := time.Date(2026, 7, 4, 0, 0, 0, 0, time.UTC)
	originDeparture := time.Date(2000, 1, 1, 23, 50, 0, 0, time.UTC)
	destinationArrival := time.Date(2000, 1, 1, 0, 10, 0, 0, time.UTC)
	cols := []string{
		"train_date", "trainno", "starting_station_id", "starting_station_name",
		"ending_station_id", "ending_station_name", "stopsequence", "train_type_id",
		"train_type_code", "train_type_name", "tripline", "stationid", "arrivaltime",
		"stationname", "mask", "note", "departuretime",
	}
	db.ExpectQuery("FROM tra_timetable WHERE stationid = ANY").
		WithArgs([]string{"1000", "1040"}, "2026-07-04", "1000", date.Format(time.TimeOnly)).
		WillReturnRows(pgxmock.NewRows(cols).
			AddRow(date, "1234", "1000", "台北", "1040", "台中", 1, "1", "1", "自強", int32(0), "1000", originDeparture, "台北", int32(0), "", originDeparture).
			AddRow(date, "1234", "1000", "台北", "1040", "台中", 5, "1", "1", "自強", int32(0), "1040", destinationArrival, "台中", int32(0), "", destinationArrival))

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
	if got := tt.Items[0].Travel_Time; got != "20m0s" {
		t.Fatalf("Travel_Time = %q, want 20m0s", got)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraTimetablePayloadQueryFiltersTimeAtOriginOnly is a SQL contract test:
// it locks the predicate and bound arguments. pgxmock matches SQL but does not
// execute the WHERE clause.
func TestTraTimetablePayloadQueryFiltersTimeAtOriginOnly(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	date := time.Date(2026, 7, 4, 23, 0, 0, 0, time.UTC)
	wantQuery := `FROM tra_timetable WHERE stationid = ANY($1) AND train_date = $2 AND (stationid <> $3 OR departuretime >= $4)`
	db.ExpectQuery(regexp.QuoteMeta(wantQuery)).
		WithArgs([]string{"1000", "1040"}, "2026-07-04", "1000", "23:00:00").
		WillReturnRows(pgxmock.NewRows([]string{"station_id"}))

	_, n, err := traTimetablePayload(context.Background(), db, "1000", "1040", date)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("leg count = %d, want 0 from empty mock rows", n)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestTraTimetablePayloadQueryHasDeterministicOrder(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	date := time.Date(2026, 7, 4, 0, 0, 0, 0, time.UTC)
	wantQuery := `FROM tra_timetable WHERE stationid = ANY($1) AND train_date = $2 AND (stationid <> $3 OR departuretime >= $4) ORDER BY trainno, stopsequence, stationid;`
	db.ExpectQuery(regexp.QuoteMeta(wantQuery)).
		WithArgs([]string{"1000", "1040"}, "2026-07-04", "1000", "00:00:00").
		WillReturnRows(pgxmock.NewRows([]string{"station_id"}))

	_, n, err := traTimetablePayload(context.Background(), db, "1000", "1040", date)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("leg count = %d, want 0", n)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestTraTimetablePayloadResolvesStationNames verifies that station names (which
// the app sends when its local station table is unavailable) are resolved to
// numeric ids — tolerating the 臺/台 split — before the timetable query.
func TestTraTimetablePayloadResolvesStationNames(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	date := time.Date(2026, 7, 4, 0, 0, 0, 0, time.UTC)
	// The app sends '台北' (台); the DB stores '臺北' (臺). Resolution must bridge.
	db.ExpectQuery("SELECT station_id FROM tra_stations").
		WithArgs("台北").
		WillReturnRows(pgxmock.NewRows([]string{"station_id"}).AddRow("1000"))
	db.ExpectQuery("SELECT station_id FROM tra_stations").
		WithArgs("花蓮").
		WillReturnRows(pgxmock.NewRows([]string{"station_id"}).AddRow("7000"))
	db.ExpectQuery("FROM tra_timetable WHERE stationid = ANY").
		WithArgs([]string{"1000", "7000"}, "2026-07-04", "1000", date.Format(time.TimeOnly)).
		WillReturnRows(pgxmock.NewRows([]string{"station_id"}))

	_, n, err := traTimetablePayload(context.Background(), db, "台北", "花蓮", date)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("leg count = %d, want 0", n)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestResolveRailStationID(t *testing.T) {
	queryErr := errors.New("station query unavailable")
	rowsErr := errors.New("station rows interrupted")
	const lookupQuery = `SELECT station_id FROM tra_stations WHERE replace(name, '臺', '台') = replace($1, '臺', '台') ORDER BY station_id LIMIT 1`

	tests := []struct {
		name       string
		input      string
		setup      func(pgxmock.PgxPoolIface)
		wantID     string
		wantErr    error
		wantAnyErr bool
	}{
		{
			name:  "query error",
			input: "台北",
			setup: func(db pgxmock.PgxPoolIface) {
				db.ExpectQuery(regexp.QuoteMeta(lookupQuery)).WithArgs("台北").WillReturnError(queryErr)
			},
			wantErr: queryErr,
		},
		{
			name:  "scan error",
			input: "台北",
			setup: func(db pgxmock.PgxPoolIface) {
				db.ExpectQuery(regexp.QuoteMeta(lookupQuery)).WithArgs("台北").
					WillReturnRows(pgxmock.NewRows([]string{"station_id"}).AddRow(struct{}{}))
			},
			wantAnyErr: true,
		},
		{
			name:  "rows error after iteration",
			input: "台北",
			setup: func(db pgxmock.PgxPoolIface) {
				db.ExpectQuery(regexp.QuoteMeta(lookupQuery)).WithArgs("台北").
					WillReturnRows(pgxmock.NewRows([]string{"station_id"}).CloseError(rowsErr))
			},
			wantErr: rowsErr,
		},
		{
			name:  "empty result returns original input",
			input: "不存在",
			setup: func(db pgxmock.PgxPoolIface) {
				db.ExpectQuery(regexp.QuoteMeta(lookupQuery)).WithArgs("不存在").
					WillReturnRows(pgxmock.NewRows([]string{"station_id"}))
			},
			wantID: "不存在",
		},
		{
			name:   "numeric id bypasses query",
			input:  "1000",
			setup:  func(pgxmock.PgxPoolIface) {},
			wantID: "1000",
		},
		{
			name:  "duplicate names select lowest station id deterministically",
			input: "台北",
			setup: func(db pgxmock.PgxPoolIface) {
				// The exact query contract selects the lowest duplicate-name ID;
				// this mock row represents that database result.
				db.ExpectQuery(regexp.QuoteMeta(lookupQuery)).WithArgs("台北").
					WillReturnRows(pgxmock.NewRows([]string{"station_id"}).AddRow("1000"))
			},
			wantID: "1000",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			db, err := pgxmock.NewPool()
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			tt.setup(db)

			got, err := resolveRailStationID(context.Background(), db, "tra_stations", tt.input)
			switch {
			case tt.wantErr != nil && !errors.Is(err, tt.wantErr):
				t.Fatalf("error = %v, want %v", err, tt.wantErr)
			case tt.wantAnyErr && err == nil:
				t.Fatal("error = nil, want scan error")
			case tt.wantErr == nil && !tt.wantAnyErr && err != nil:
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.wantID {
				t.Fatalf("station id = %q, want %q", got, tt.wantID)
			}
			if err := db.ExpectationsWereMet(); err != nil {
				t.Fatal(err)
			}
		})
	}
}
