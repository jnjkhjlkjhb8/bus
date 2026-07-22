package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

type thsrTimetableRow struct {
	Trainno               string `db:"trainno"`
	Starting_station_id   string `db:"starting_station_id"`
	Starting_station_name string `db:"starting_station_name"`
	Ending_station_id     string `db:"ending_station_id"`
	Ending_station_name   string `db:"ending_station_name"`
	Arrivaltime           string `db:"arrivaltime"`
	Departuretime         string `db:"departuretime"`
	Note                  string `db:"note"`
	Overnight             bool   `db:"overnight"`
	Stationid             string `db:"stationid"`
	Stopsequence          int    `db:"stopsequence"`
}
type thsrStopsRow struct {
	Stopsequence  int    `db:"stopsequence"`
	Stationid     string `db:"stationid"`
	Stationname   string `db:"stationname"`
	Arrivaltime   string `db:"arrivaltime"`
	Departuretime string `db:"departuretime"`
}
type thsrfare struct {
	TicketType uint8 `db:"ticket_type"`
	FareClass  uint8 `db:"fare_class"`
	CabinClass uint8 `db:"cabin_class"`
	Price      int32 `db:"price"`
}

// thsrFarePayload reads a THSR fare from the loaded env schema and returns the
// marshaled ThsaFares proto. It is a pure read: an unlanded fare stays empty and
// the router never fetches from TDX (ADR-0005).
//
// TDX prices each pair across three axes: ticket type, fare class (1 全票 /
// 9 半票 — 孩童, 敬老 and 愛心 all ride at 半票) and cabin class (1 標準對號 /
// 2 商務 / 3 自由座), so 南港→左營 alone lands eight rows from 740 to 2500.
//
// Only ticket_type is pinned, to 1 (單程): the return-trip types belong to a
// booking flow, not a fare quote. The fare-class and cabin-class axes are left
// open so the app can quote the rider's own 票種 and seat. The app selects the
// row; leaving these axes open is only safe because no caller quotes Items[0]
// as "the" fare (services/router/handlers_core.go returns the whole set).
func thsrFarePayload(ctx context.Context, start, end string, db railDB) ([]byte, error) {
	arr, err := queryThsrFares(ctx, db, start, end)
	if err != nil {
		return nil, err
	}
	return proto.Marshal(&models.ThsaFares{Items: arr})
}
func queryThsrFares(ctx context.Context, db railDB, start, end string) ([]*models.ThsaFare, error) {
	start, err := resolveRailStationID(ctx, db, "thsr_stations", start)
	if err != nil {
		return nil, err
	}
	end, err = resolveRailStationID(ctx, db, "thsr_stations", end)
	if err != nil {
		return nil, err
	}
	rows, err := db.Query(ctx, `SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares WHERE origin_station_id = $1 AND destination_station_id = $2 AND ticket_type = 1 AND price > 0 ORDER BY cabin_class, fare_class, price;`, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrfare])
	if err != nil {
		return nil, err
	}
	arr := make([]*models.ThsaFare, 0, len(row))
	for _, temp := range row {
		arr = append(arr, &models.ThsaFare{
			CabinClas:  int32(temp.CabinClass),
			TicketType: int32(temp.TicketType),
			FareClass:  int32(temp.FareClass),
			Price:      temp.Price,
		})
	}
	return arr, rows.Err()
}

// thsrStoptimesPayload reads a THSR train's stop times for a date from the loaded
// env schema and returns the marshaled ThsrStoptimes proto plus the row count. A
// zero count signals NotFound (ADR-0005); it never fetches from TDX.
func thsrStoptimesPayload(ctx context.Context, db railDB, trainno, dateStr string) ([]byte, int, error) {
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime FROM thsr_timetable WHERE trainno = $1 AND train_date = $2 ORDER BY stopsequence;`
	rows, err := db.Query(ctx, q, trainno, dateStr)
	if err != nil {
		return nil, 0, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrStopsRow])
	if err != nil {
		return nil, 0, err
	}
	arr := make([]*models.ThsaStoptime, 0, len(row))
	for _, temp := range row {
		arr = append(arr, &models.ThsaStoptime{
			StopSequence:  int32(temp.Stopsequence),
			StationId:     temp.Stationid,
			StationName:   temp.Stationname,
			ArrivalTime:   temp.Arrivaltime,
			DepartureTime: temp.Departuretime,
		})
	}
	b, err := proto.Marshal(&models.ThsrStoptimes{Items: arr})
	if err != nil {
		return nil, 0, err
	}
	return b, len(row), nil
}

// thsrTimetablePayload reads THSR services calling at both the origin and
// destination for a date, pairs them into origin/destination legs, and returns
// the marshaled ThsrTimetables proto plus the number of paired legs. A zero count
// signals NotFound (ADR-0005); it never fetches from TDX.
func thsrTimetablePayload(ctx context.Context, db railDB, start, end string, date time.Time) ([]byte, int, error) {
	start, err := resolveRailStationID(ctx, db, "thsr_stations", start)
	if err != nil {
		return nil, 0, err
	}
	end, err = resolveRailStationID(ctx, db, "thsr_stations", end)
	if err != nil {
		return nil, 0, err
	}
	const combined = `SELECT trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name,arrivaltime,departuretime,note,overnight,stationid,stopsequence FROM thsr_timetable WHERE stationid = ANY($1) AND train_date = $2 ORDER BY trainno, stopsequence, stationid;`
	stations := []string{start, end}
	rows, err := db.Query(ctx, combined, stations, date.Format(time.DateOnly))
	if err != nil {
		return nil, 0, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrTimetableRow])
	if err != nil {
		return nil, 0, err
	}
	mp := make(map[string]*models.ThsaTimetable)
	startSeq := make(map[string]int)
	arr := []*models.ThsaTimetable{}
	for _, temp := range row {
		if temp.Stationid != start {
			continue
		}
		if temp.Departuretime < date.Format(time.TimeOnly) {
			continue
		}
		startSeq[temp.Trainno] = temp.Stopsequence
		mp[temp.Trainno] = &models.ThsaTimetable{
			TrainDate:             date.Format(time.DateOnly),
			TrainNo:               temp.Trainno,
			Starting_Station_Name: temp.Starting_station_name,
			EndingStationName:     temp.Ending_station_name,
			Note:                  temp.Note,
			Overnight:             temp.Overnight,
			Starting_Time:         temp.Departuretime,
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
		w, err := time.Parse(time.TimeOnly, seed.Starting_Time)
		if err != nil {
			log.Errorf("parse time error: %v", err)
			continue
		}
		t, err := time.Parse(time.TimeOnly, temp.Arrivaltime)
		if err != nil {
			log.Errorf("parse time error: %v", err)
			continue
		}
		duration := t.Sub(w)
		if duration < 0 {
			duration += 24 * time.Hour
		}
		seed.Ending_Time = temp.Arrivaltime
		seed.Travel_Time = duration.String()
		arr = append(arr, seed)
	}
	b, err := proto.Marshal(&models.ThsrTimetables{Items: arr})
	if err != nil {
		return nil, 0, err
	}
	return b, len(arr), nil
}
