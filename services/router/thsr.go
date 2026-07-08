package main

import (
	"context"
	"fmt"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

type thsrTimetableRow struct {
	Trainno               string `db:"trainno"`
	Starting_station_id   string `db:"starting_station_id"`
	Starting_station_name string `db:"starting_station_name"`
	Ending_station_id     string `db:"ending_station_id"`
	Ending_station_name   string `db:"ending_station_name"`
	Arrivaltime           string `db:"arrivaltime"`
	Note                  string `db:"note"`
	Overnight             bool   `db:"overnight"`
	Stationid             string `db:"stationid"`
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
type raw_thsr_availableseatstatus struct {
	TrainDate string `json:"TrainDate"`
	Items     []struct {
		TrainNo           string `json:"TrainNo"`
		Direction         uint8  `json:"Direction"`
		OriginStationID   string `json:"OriginStationID"`
		OriginStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"OriginStationName"`
		DestinationStationID   string `json:"DestinationStationID"`
		DestinationStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"DestinationStationName"`
		StandardSeatStatus string `json:"StandardSeatStatus"`
		BusinessSeatStatus string `json:"BusinessSeatStatus"`
	} `json:"Items"`
}

// thsrFarePayload reads a THSR fare from the loaded env schema and returns the
// marshaled ThsaFares proto. refresh is a legacy hook invoked once when the DB
// is empty; the read path passes nil so an unlanded fare stays empty (ADR-0005).
func thsrFarePayload(ctx context.Context, start, end string, db railDB, refresh func()) ([]byte, error) {
	arr, err := queryThsrFares(ctx, db, start, end)
	if err != nil {
		return nil, err
	}
	if len(arr) == 0 && refresh != nil {
		refresh()
		arr, err = queryThsrFares(ctx, db, start, end)
		if err != nil {
			return nil, err
		}
	}
	return proto.Marshal(&models.ThsaFares{Items: arr})
}
func queryThsrFares(ctx context.Context, db railDB, start, end string) ([]*models.ThsaFare, error) {
	rows, err := db.Query(ctx, `SELECT ticket_type, fare_class, cabin_class, price FROM thsr_fares WHERE origin_station_id = $1 AND destination_station_id = $2;`, start, end)
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
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime FROM thsr_timetable WHERE trainno = $1 AND train_date = $2;`
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
	start = resolveRailStationID(ctx, db, "thsr_stations", start)
	end = resolveRailStationID(ctx, db, "thsr_stations", end)
	const combined = `SELECT trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name,arrivaltime,note,overnight,stationid FROM thsr_timetable WHERE stationid = ANY($1) AND train_date = $2;`
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
	arr := []*models.ThsaTimetable{}
	for _, temp := range row {
		if temp.Stationid != start {
			continue
		}
		if temp.Arrivaltime < date.Format(time.TimeOnly) {
			continue
		}
		mp[temp.Trainno] = &models.ThsaTimetable{
			TrainDate:             date.Format(time.DateOnly),
			TrainNo:               temp.Trainno,
			Starting_Station_Name: temp.Starting_station_name,
			EndingStationName:     temp.Ending_station_name,
			Note:                  temp.Note,
			Overnight:             temp.Overnight,
			Starting_Time:         temp.Arrivaltime,
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
		w, err := time.Parse(time.TimeOnly, seed.Starting_Time)
		if err != nil {
			log.Infof("parse time error: %v", err)
			continue
		}
		t, err := time.Parse(time.TimeOnly, temp.Arrivaltime)
		if err != nil {
			log.Infof("parse time error: %v", err)
			continue
		}
		duration := t.Sub(w)
		if seed.Overnight {
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

// get_thsr_availableseatstatus refreshes the realtime THSR available-seat cache
// from TDX and republishes it over Redis Pub/Sub. It backs the AvailableSeats
// stream and is intentionally kept on the router (out of ADR-0005 scope).
func get_thsr_availableseatstatus(tdx *shared.TDXClient, rc *redis.Client, Date string) {
	log.Infof("[RAIL] action=thsr_AvailableSeatStatus event=start")
	dec, comp, flipopen, err := tdx.Get(fmt.Sprintf("/v2/Rail/THSR/AvailableSeatStatus/Train/OD/TrainDate/%s", Date), "thsr_traindate")
	if err != nil || !comp {
		log.Infof("[RAIL] action=thsr_AvailableSeatStatus event=skip reason=api_error")
		return
	}
	defer flipopen()
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_AvailableSeatStatus event=decode_error error=%v", err)
		return
	}
	row := make(map[string]*models.ThsrAvailableSeats)
	for dec.More() {
		var temp raw_thsr_availableseatstatus
		if err := dec.Decode(&temp); err == nil {
			for _, stop := range temp.Items {
				if row[stop.TrainNo] == nil {
					row[stop.TrainNo] = &models.ThsrAvailableSeats{}
				}
				row[stop.TrainNo].Segments = append(row[stop.TrainNo].Segments, &models.ThsrSeatSegment{
					OriginStationId:      stop.OriginStationID,
					DestinationStationId: stop.DestinationStationID,
					StandardSeatStatus:   stop.StandardSeatStatus,
					BusinessSeatStatus:   stop.BusinessSeatStatus,
				})
			}
		}
	}
	pipe := rc.Pipeline()
	count := 0
	for trainNo, seats := range row {
		pb, err := proto.Marshal(seats)
		if err != nil {
			continue
		}
		key := shared.ThsrSeatsKey(Date, trainNo)
		pipe.Set(key, pb, 15*time.Minute)
		pipe.Publish(key, string(pb))
		count++
	}
	if _, err = pipe.Exec(); err != nil {
		log.Infof("[THSR_SEATS] action=thsr_AvailableSeatStatus event=redis_error error=%v", err)
	} else {
		log.Infof("[THSR_SEATS] action=thsr_AvailableSeatStatus event=success train_count=%d", count)
	}
}
