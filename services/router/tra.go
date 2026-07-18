package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

// railDB is the read surface the rail handlers need. Both *pgxpool.Pool and the
// pgxmock pool satisfy it, so read-path helpers can be unit-tested with a mock.
type railDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

type traTimetableRow struct {
	Train_date            time.Time `db:"train_date"`
	Trainno               string    `db:"trainno"`
	Starting_station_id   string    `db:"starting_station_id"`
	Starting_station_name string    `db:"starting_station_name"`
	Ending_station_id     string    `db:"ending_station_id"`
	Ending_station_name   string    `db:"ending_station_name"`
	Train_type_id         string    `db:"train_type_id"`
	Train_type_code       string    `db:"train_type_code"`
	Train_type_name       string    `db:"train_type_name"`
	Tripline              int32     `db:"tripline"`
	Stopsequence          int       `db:"stopsequence"`
	Stationid             string    `db:"stationid"`
	Stationname           string    `db:"stationname"`
	Arrivaltime           time.Time `db:"arrivaltime"`
	Departuretime         time.Time `db:"departuretime"`
	Mask                  int32     `db:"mask"`
	Note                  string    `db:"note"`
}
type traStopsRow struct {
	Stopsequence  int    `db:"stopsequence"`
	Stationid     string `db:"stationid"`
	Stationname   string `db:"stationname"`
	Arrivaltime   string `db:"arrivaltime"`
	Departuretime string `db:"departuretime"`
	Mask          int32  `db:"mask"`
}
type trafare struct {
	TicketType string `db:"ticket_type"`
	Price      int32  `db:"price"`
}

// traAdultTicketTypes are the TDX ticket types for a full-price adult ticket,
// one per train class: 自強 (incl. 太魯閣/普悠瑪/EMU3000), 莒光, 復興 — which is
// also the 區間車 tier — and 普快. TDX packs 票種 and 車種 into a single
// ticket_type string, so a pair yields four different adult prices (e.g.
// 桃園→臺北: 成自 99, 成莒 76, 成復 63, 成普 31); the caller picks by the train's
// class. Excluded are the 孩/愛 (child/disabled) and 折 (return-trip discount)
// variants, which are not the full adult fare.
var traAdultTicketTypes = []string{"成自", "成莒", "成復", "成普"}

// traFarePayload reads a TRA pair's adult fares from the loaded env schema and
// returns the marshaled TraFareItems proto, one item per train class, priciest
// first. It returns an empty slice (not an error) when no rows match, so callers
// treat an unlanded date as NotFound (ADR-0005); it never fetches from TDX.
func traFarePayload(ctx context.Context, db railDB, start, end string) ([]byte, error) {
	start, err := resolveRailStationID(ctx, db, "tra_stations", start)
	if err != nil {
		return nil, err
	}
	end, err = resolveRailStationID(ctx, db, "tra_stations", end)
	if err != nil {
		return nil, err
	}
	const q = `SELECT ticket_type,price FROM tra_fares WHERE origin_station_id = $1 AND destination_station_id = $2 AND ticket_type = ANY($3) AND price > 0 ORDER BY price DESC, ticket_type;`
	rows, err := db.Query(ctx, q, start, end, traAdultTicketTypes)
	if err != nil {
		return nil, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[trafare])
	if err != nil {
		return nil, err
	}
	if len(row) == 0 {
		return nil, nil
	}
	arr := make([]*models.TraFareItem, 0, len(row))
	for _, temp := range row {
		arr = append(arr, &models.TraFareItem{
			TicketType: temp.TicketType,
			Price:      temp.Price,
		})
	}
	return proto.Marshal(&models.TraFareItems{Items: arr})
}

// traStoptimesPayload reads a TRA train's stop times for a date from the loaded
// env schema and returns the marshaled TraStoptimes proto plus the row count. A
// zero count signals NotFound (ADR-0005); it never fetches from TDX.
func traStoptimesPayload(ctx context.Context, db railDB, trainno, dateStr string) ([]byte, int, error) {
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime,mask FROM tra_timetable WHERE trainno = $1 AND train_date = $2 ORDER BY stopsequence;`
	rows, err := db.Query(ctx, q, trainno, dateStr)
	if err != nil {
		return nil, 0, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traStopsRow])
	if err != nil {
		return nil, 0, err
	}
	arr := make([]*models.TraStoptime, 0, len(row))
	for _, temp := range row {
		arr = append(arr, &models.TraStoptime{
			StopSequence:  int32(temp.Stopsequence),
			StationId:     temp.Stationid,
			StationName:   temp.Stationname,
			ArrivalTime:   temp.Arrivaltime,
			DepartureTime: temp.Departuretime,
			SuspendedFlag: (temp.Mask & (1 << 7)) != 0,
		})
	}
	b, err := proto.Marshal(&models.TraStoptimes{Items: arr})
	if err != nil {
		return nil, 0, err
	}
	return b, len(row), nil
}

// isNumericStationID reports whether s is already a numeric station code (TRA
// and THSR ids are digit strings) rather than a station name needing resolution.
func isNumericStationID(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// resolveRailStationID maps a station name to its numeric station_id, tolerating
// the 臺/台 spelling split (TDX data stores 臺, the app's labels use 台). Inputs
// that are already numeric ids, or that match no station, are returned as-is.
// Database errors are returned to the caller rather than treated as a miss.
// table is a caller-supplied constant ("tra_stations"/"thsr_stations").
func resolveRailStationID(ctx context.Context, db railDB, table, s string) (string, error) {
	if isNumericStationID(s) {
		return s, nil
	}
	rows, err := db.Query(ctx,
		`SELECT station_id FROM `+table+
			` WHERE replace(name, '臺', '台') = replace($1, '臺', '台') ORDER BY station_id LIMIT 1`, s)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	if rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return "", err
		}
		return id, nil
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	return s, nil
}

// traTimetablePayload reads TRA services calling at both the origin and
// destination for a date, pairs them into origin/destination legs, and returns
// the marshaled TraTimetables proto plus the number of paired legs. A zero count
// signals NotFound (ADR-0005); it never fetches from TDX.
func traTimetablePayload(ctx context.Context, db railDB, start, end string, date time.Time) ([]byte, int, error) {
	start, err := resolveRailStationID(ctx, db, "tra_stations", start)
	if err != nil {
		return nil, 0, err
	}
	end, err = resolveRailStationID(ctx, db, "tra_stations", end)
	if err != nil {
		return nil, 0, err
	}
	const combined = `SELECT train_date,trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name, stopsequence,train_type_id,train_type_code,train_type_name,tripline,stationid,arrivaltime,stationname,mask,note,departuretime FROM tra_timetable WHERE stationid = ANY($1) AND train_date = $2 AND (stationid <> $3 OR departuretime >= $4) ORDER BY trainno, stopsequence, stationid;`
	stations := []string{start, end}
	rows, err := db.Query(ctx, combined, stations, date.Format(time.DateOnly), start, date.Format(time.TimeOnly))
	if err != nil {
		return nil, 0, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traTimetableRow])
	if err != nil {
		return nil, 0, err
	}
	mp := make(map[string]*models.TraTimetable)
	startSeq := make(map[string]int)
	arr := []*models.TraTimetable{}
	for _, temp := range row {
		if temp.Stationid == start {
			startSeq[temp.Trainno] = temp.Stopsequence
			mp[temp.Trainno] = &models.TraTimetable{
				TrainDate:             temp.Train_date.Format(time.DateOnly),
				TrainNo:               temp.Trainno,
				Starting_Station_Name: temp.Starting_station_name,
				Ending_Station_Name:   temp.Ending_station_name,
				TrainTypeCode:         temp.Train_type_code,
				TrainTypeName:         temp.Train_type_name,
				TrainTypeID:           temp.Train_type_id,
				TripLine:              temp.Tripline,
				Mask:                  temp.Mask,
				Note:                  temp.Note,
				// The origin leg is a departure, not an arrival: a train
				// originating at the queried station has no arrival time there.
				Starting_Time: temp.Departuretime.Format(time.RFC3339),
			}
		}
	}
	for _, temp := range row {
		if temp.Stationid != end {
			continue
		}
		seed, ok := mp[temp.Trainno]
		if !ok {
			continue
		}
		if temp.Stopsequence <= startSeq[temp.Trainno] {
			continue
		}
		w, err := time.Parse(time.RFC3339, seed.Starting_Time)
		if err != nil {
			log.Errorf("parse time error: %v", err)
			continue
		}
		t := temp.Arrivaltime
		duration := t.Sub(w)
		if duration < 0 {
			duration += 24 * time.Hour
		}
		seed.Ending_Time = t.Format(time.RFC3339)
		seed.Travel_Time = duration.String()
		arr = append(arr, seed)
	}
	b, err := proto.Marshal(&models.TraTimetables{Items: arr})
	if err != nil {
		return nil, 0, err
	}
	return b, len(arr), nil
}
