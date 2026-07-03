package main

import (
	"context"
	"fmt"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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
type thsrFareDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}
type raw_thsrfare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	TicketType           uint8  `json:"TicketType"`
	FareClass            uint8  `json:"FareClass"`
	CabinClass           uint8  `json:"CabinClass"`
	Price                int32  `json:"Price"`
}
type raw_thsr_timetable struct {
	TrainDate      string `json:"TrainDate"`
	DailyTrainInfo struct {
		TrainNo             string `json:"TrainNo"`
		Direction           uint8  `json:"Direction"`
		StartingStationID   string `json:"StartingStationID"`
		StartingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StartingStationName"`
		EndingStationID   string `json:"EndingStationID"`
		EndingStationName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"EndingStationName"`
		Note struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"Note"`
		Overnight bool `json:"Overnight"`
	} `json:"DailyTrainInfo"`
	StopTimes []struct {
		StopSequence uint8  `json:"StopSequence"`
		StationID    string `json:"StationID"`
		StationName  struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StationName"`
		ArrivalTime   string `json:"ArrivalTime"`
		DepartureTime string `json:"DepartureTime"`
	} `json:"StopTimes"`
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

func thsr_price(ctx context.Context, start, end string, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	bytes, err := thsrFarePayload(ctx, start, end, db, func() {
		getthsrfares(ctx, client, rc, db)
	})
	if err != nil {
		log.Infof("thsr fare error: %v", err)
		return
	}
	if err = rc.Set(fmt.Sprintf("THSR_Fare:%s:%s", start, end), bytes, 1*time.Hour).Err(); err != nil {
		log.Infof("redis set error: %v", err)
	}
}
func thsrFarePayload(ctx context.Context, start, end string, db thsrFareDB, refresh func()) ([]byte, error) {
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
func queryThsrFares(ctx context.Context, db thsrFareDB, start, end string) ([]*models.ThsaFare, error) {
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
func thsr_stoptimes(ctx context.Context, trainno string, date time.Time, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime FROM thsr_timetable WHERE trainno = $1 AND train_date = $2;`
	dateStr := date.Format(time.DateOnly)
	rows, _ := db.Query(ctx, q, trainno, dateStr)
	row, _ := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrStopsRow])
	rows.Close()
	if len(row) == 0 {
		get_thsr_timetable(ctx, db, client, rc, dateStr)
		rows, _ = db.Query(ctx, q, trainno, dateStr)
		row, _ = pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrStopsRow])
		rows.Close()
	}
	arr := []*models.ThsaStoptime{}
	for _, temp := range row {
		arr = append(arr, &models.ThsaStoptime{
			StopSequence:  int32(temp.Stopsequence),
			StationId:     temp.Stationid,
			StationName:   temp.Stationname,
			ArrivalTime:   temp.Arrivaltime,
			DepartureTime: temp.Departuretime,
		})
	}
	bytes, err := proto.Marshal(&models.ThsrStoptimes{Items: arr})
	if err != nil {
		log.Infof("proto marshal error: %v", err)
		return
	}
	if err = rc.Set(fmt.Sprintf("THSR_Stoptimes:%s:%s", dateStr, trainno), bytes, 1*time.Hour).Err(); err != nil {
		log.Infof("redis set error: %v", err)
	}
}
func thsr_timetable(ctx context.Context, start, end string, date time.Time, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	mp := make(map[string]*models.ThsaTimetable)
	arr := []*models.ThsaTimetable{}
	combined := `SELECT trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name,arrivaltime,note,overnight,stationid FROM thsr_timetable WHERE stationid = ANY($1) AND train_date = $2;`
	stations := []string{start, end}
	rows, _ := db.Query(ctx, combined, stations, date.Format(time.DateOnly))
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrTimetableRow])
	rows.Close()
	if len(row) == 0 {
		get_thsr_timetable(ctx, db, client, rc, date.Format(time.DateOnly))
		rows, _ = db.Query(ctx, combined, stations, date.Format(time.DateOnly))
		row, err = pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrTimetableRow])
		rows.Close()
	}
	if err != nil {
		log.Infoln(err.Error())
	}
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
	bytes, err := proto.Marshal(&models.ThsrTimetables{Items: arr})
	if err != nil {
		log.Infof("proto marshal error: %v", err)
	} else {
		if err = rc.Set(fmt.Sprintf("THSR_timetable:%s:%s:%s", date.Format(time.DateOnly), start, end), bytes, 1*time.Hour).Err(); err != nil {
			log.Infof("redis set error: %v", err)
		}
	}
}
func get_thsr_timetable(ctx context.Context, db *pgxpool.Pool, client *resty.Client, rc *redis.Client, Date string) {
	log.Infof("[RAIL] action=thsr_timetable event=start")
	dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/THSR/DailyTimetable/TrainDate/%s", Date), "thsr_traindate")
	if err != nil || !comp {
		log.Infof("[RAIL] action=thsr_timetable event=skip reason=api_error")
		return
	}
	defer flipopen()
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_timetable event=decode_error error=%v", err)
		return
	}
	var row [][]interface{}
	for dec.More() {
		var temp raw_thsr_timetable
		if err := dec.Decode(&temp); err == nil {
			for _, stop := range temp.StopTimes {
				row = append(row, []interface{}{
					temp.TrainDate,
					temp.DailyTrainInfo.TrainNo,
					temp.DailyTrainInfo.Direction,
					temp.DailyTrainInfo.StartingStationID,
					temp.DailyTrainInfo.StartingStationName.ZhTw,
					temp.DailyTrainInfo.EndingStationID,
					temp.DailyTrainInfo.EndingStationName.ZhTw,
					stop.StationID,
					stop.StationName.ZhTw,
					stop.ArrivalTime,
					stop.DepartureTime,
					temp.DailyTrainInfo.Note.ZhTw,
					temp.DailyTrainInfo.Overnight,
				})
			}
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_thsr (
					train_date          date not null,
					trainno             text not null,
					direction           integer,
					starting_station_id text not null,
					starting_station_name text not null,
					ending_station_id   text not null,
					ending_station_name  text not null,
					stopsequence        smallint,
					stationid           text,
					stationname         text,
					arrivaltime         time,
					departuretime       time,
					note                text,
					overnight           boolean,
					updated_at          timestamp with time zone
				) ON COMMIT DROP;`
		c2 := `INSERT INTO thsr_timetable (
				train_date,
				trainno,
				direction,
				starting_station_id,
				starting_station_name,
				ending_station_id,
				ending_station_name,
				stopsequence,
				stationid,
				stationname,
				arrivaltime,
				departuretime,
				note,
				overnight,
				updated_at
			)
			SELECT train_date,trainno,direction,starting_station_id,starting_station_name,ending_station_id,ending_station_name,stopsequence,stationid,stationname,arrivaltime,departuretime,note,overnight,NOW()
			FROM temp_thsr
			ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET direction = EXCLUDED.direction, starting_station_id = EXCLUDED.starting_station_id,starting_station_name = excluded.starting_station_name,ending_station_name = excluded.ending_station_name, ending_station_id = EXCLUDED.ending_station_id,stopsequence = excluded.stopsequence, stationname = excluded.stationname, arrivaltime = excluded.arrivaltime, departuretime = excluded.departuretime,note = excluded.note, overnight = excluded.overnight, updated_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[RAIL] action=thsr_timetable event=tx_error error=%v", err)
			return
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[RAIL] action=timetable event=create_temp_error error=%v", err)
			return
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_thsr"}, []string{"train_date", "trainno", "direction", "starting_station_id", "starting_station_name", "ending_station_id", "ending_station_name", "stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "note", "overnight"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, err = b.Exec(ctx, c2); err != nil {
				log.Infof("[RAIL] action=thsr_timetable event=exec_error error=%v", err)
				return
			}
			if err = b.Commit(ctx); err != nil {
				log.Infof("[RAIL] action=thsr_timetable event=commit_error error=%v", err)
			} else {
				log.Infof("[RAIL] action=thsr_timetable event=success timetable_count=%d", len(row))
			}
		} else {
			log.Infof("[RAIL] action=thsr_timetable event=copyfrom_error error=%v", err)
		}
	} else {
		log.Infof("[RAIL] action=thsr_timetable event=complete reason=no_data")
	}
	log.Infof("[RAIL] action=thsr_timetable event=complete")
}
func get_thsr_availableseatstatus(client *resty.Client, rc *redis.Client, Date string) {
	log.Infof("[RAIL] action=thsr_AvailableSeatStatus event=start")
	dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/THSR/AvailableSeatStatus/Train/OD/TrainDate/%s", Date), "thsr_traindate")
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
		key := fmt.Sprintf("thsr_seats:%s:%s", Date, trainNo)
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
func getthsrfares(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) {
	log.Infof("[RAIL] action=get_thsr_fare event=start")
	dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/THSR/ODFare"), "thsr_fare")
	if err != nil || !comp {
		log.Infof("[RAIL] action=get_thsr_fare event=skip reason=api_error")
		return
	}
	func() {
		defer flipopen()
		if _, err := dec.Token(); err != nil {
			log.Infof("[RAIL] action=get_thsr_fare event=decode_error error=%v", err)
			return
		}
		var row [][]interface{}
		for dec.More() {
			var temp raw_thsrfare
			if err := dec.Decode(&temp); err == nil {
				row = append(row, []interface{}{
					temp.OriginStationID,
					temp.DestinationStationID,
					temp.TicketType,
					temp.FareClass,
					temp.CabinClass,
					temp.Price,
				})
			}
		}
		if len(row) > 0 {
			c1 := `CREATE TEMP TABLE temp_thsr (
					osi text,
					dsi text,
					ty smallint,
					fare smallint,
					cabin smallint,
					p smallint
				) ON COMMIT DROP;`
			c2 := `INSERT INTO thsr_fares (
					origin_station_id,
					destination_station_id,
					ticket_type,
					fare_class,
                    cabin_class,
					price,
					updated_at
				)
				SELECT osi, dsi, ty, fare,cabin,p,NOW() FROM temp_thsr
				ON CONFLICT (origin_station_id,destination_station_id,ticket_type,fare_class,cabin_class) DO UPDATE SET price = EXCLUDED.price,updated_at = NOW();`
			b, err := db.Begin(ctx)
			if err != nil {
				log.Infof("[rail] action=get_tra_fare event=begin_error error=%v", err)
				return
			}
			defer func(b pgx.Tx, ctx context.Context) {
				_ = b.Rollback(ctx)
			}(b, ctx)
			if _, err := b.Exec(ctx, c1); err != nil {
				log.Infof("[RAIL] action=get_thsr_fare event=create_temp_error error=%v", err)
				return
			}
			_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_thsr"}, []string{"osi", "dsi", "ty", "fare", "cabin", "p"}, pgx.CopyFromRows(row))
			if err == nil {
				if _, execErr := b.Exec(ctx, c2); execErr != nil {
					log.Infof("[RAIL] action=get_thsr_fare event=exec_error error=%v", execErr)
				}
				if commitErr := b.Commit(ctx); commitErr != nil {
					log.Infof("[rail] action=get_thsr_fare event=commit_error error=%v", commitErr)
				} else {
					log.Infof("[rail] action=get_thsr_fare event=success station_count=%d", len(row))
				}
			} else {
				log.Infof("[rail] action=get_thsr_fare event=copyfrom_error error=%v", err)
				_ = b.Rollback(ctx)
			}
		}
	}()
	log.Infof("[rail] action=get_thsr_fare event=complete")
}
