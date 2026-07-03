package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

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
type raw_trafare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	TicketType           string `json:"TicketType"`
	Price                int32  `json:"Price"`
}
type raw_tra_timetable struct {
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
		TrainTypeID   string `json:"TrainTypeID"`
		TrainTypeCode string `json:"TrainTypeCode"`
		TrainTypeName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"TrainTypeName"`
		TripLine           uint8 `json:"TripLine"`
		WheelchairFlag     uint8 `json:"WheelchairFlag"`
		PackageServiceFlag uint8 `json:"PackageServiceFlag"`
		DiningFlag         uint8 `json:"DiningFlag"`
		BikeFlag           uint8 `json:"BikeFlag"`
		BreastFeedingFlag  uint8 `json:"BreastFeedingFlag"`
		DailyFlag          uint8 `json:"DailyFlag"`
		ServiceAddedFlag   uint8 `json:"ServiceAddedFlag"`
		SuspendedFlag      uint8 `json:"SuspendedFlag"`
		Note               struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"Note"`
	} `json:"DailyTrainInfo"`
	StopTimes []struct {
		StopSequence uint8  `json:"StopSequence"`
		StationID    string `json:"StationID"`
		StationName  struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StationName"`
		ArrivalTime   string `json:"ArrivalTime"`
		DepartureTime string `json:"DepartureTime"`
		SuspendedFlag uint8  `json:"SuspendedFlag"`
	} `json:"StopTimes"`
}

func tra_price(ctx context.Context, start, end string, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	const q = `SELECT ticket_type,price FROM tra_fares WHERE origin_station_id = $1 AND destination_station_id = $2;`
	rows, _ := db.Query(ctx, q, start, end)
	row, _ := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[trafare])
	rows.Close()
	if len(row) == 0 {
		gettrafares(ctx, client, rc, db)
		rows, _ = db.Query(ctx, q, start, end)
		row, _ = pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[trafare])
		rows.Close()
	}
	arr := []*models.TraFareItem{}
	for _, temp := range row {
		arr = append(arr, &models.TraFareItem{
			TicketType: temp.TicketType,
			Price:      temp.Price,
		})
	}
	bytes, err := proto.Marshal(&models.TraFareItems{Items: arr})
	if err != nil {
		log.Infof("proto marshal error: %v", err)
		return
	}
	if err = rc.Set(fmt.Sprintf("TRA_Fare:%s:%s", start, end), bytes, 8*time.Hour).Err(); err != nil {
		log.Infof("redis set error: %v", err)
	}
}
func tra_stoptimes(ctx context.Context, trainno string, date time.Time, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime,mask FROM tra_timetable WHERE trainno = $1 AND train_date = $2;`
	dateStr := date.Format(time.DateOnly)
	rows, _ := db.Query(ctx, q, trainno, dateStr)
	row, _ := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traStopsRow])
	rows.Close()
	if len(row) == 0 {
		get_tra_timetable(ctx, db, client, rc, dateStr)
		rows, _ = db.Query(ctx, q, trainno, dateStr)
		row, _ = pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traStopsRow])
		rows.Close()
	}
	arr := []*models.TraStoptime{}
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
	bytes, err := proto.Marshal(&models.TraStoptimes{Items: arr})
	if err != nil {
		log.Infof("proto marshal error: %v", err)
		return
	}
	if err = rc.Set(fmt.Sprintf("TRA_Stoptimes:%s:%s", dateStr, trainno), bytes, 1*time.Hour).Err(); err != nil {
		log.Infof("redis set error: %v", err)
	}
}
func tra_timetable(ctx context.Context, start, end string, date time.Time, client *resty.Client, db *pgxpool.Pool, rc *redis.Client) {
	mp := make(map[string]*models.TraTimetable)
	arr := []*models.TraTimetable{}
	combined := `SELECT train_date,trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name, stopsequence,train_type_id,train_type_code,train_type_name,tripline,stationid,arrivaltime,stationname,mask,note,departuretime FROM tra_timetable WHERE stationid = ANY($1) AND train_date = $2 AND arrivaltime >= $3;`
	stations := []string{start, end}
	rows, _ := db.Query(ctx, combined, stations, date.Format(time.DateOnly), date.Format(time.TimeOnly))
	row, _ := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traTimetableRow])
	rows.Close()
	if len(row) == 0 {
		get_tra_timetable(ctx, db, client, rc, date.Format(time.DateOnly))
		rows, _ = db.Query(ctx, combined, stations, date.Format(time.DateOnly), date.Format(time.TimeOnly))
		row, _ = pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traTimetableRow])
		rows.Close()
	}
	for _, temp := range row {
		if temp.Stationid == start {
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
				Starting_Time:         temp.Arrivaltime.Format(time.RFC3339),
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
		w, err := time.Parse(time.RFC3339, seed.Starting_Time)
		if err != nil {
			log.Infof("parse time error: %v", err)
			continue
		}
		t := temp.Arrivaltime
		duration := t.Sub(w)
		if duration < 0 {
			duration = -duration
		}
		seed.Ending_Time = t.Format(time.RFC3339)
		seed.Travel_Time = duration.String()
		arr = append(arr, seed)
	}
	bytes, err := proto.Marshal(&models.TraTimetables{Items: arr})
	if err != nil {
		log.Infof("proto marshal error: %v", err)
	} else {
		if err = rc.Set(fmt.Sprintf("TRA_timetable:%s:%s:%s", date.Format(time.DateOnly), start, end), bytes, 1*time.Hour).Err(); err != nil {
			log.Infof("redis set error: %v", err)
		}
	}
}
func get_tra_timetable(ctx context.Context, db *pgxpool.Pool, client *resty.Client, rc *redis.Client, Date string) {
	log.Infof("[RAIL] action=tra_timetable event=start")
	dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/TRA/DailyTimetable/TrainDate/%s", Date), "tra_traindate")
	if err != nil || !comp {
		log.Infof("[RAIL] action=tra_timetable event=skip reason=api_error")
		return
	}
	defer flipopen()
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_timetable event=decode_error error=%v", err)
		return
	}
	var row [][]interface{}
	for dec.More() {
		var temp raw_tra_timetable
		if err := dec.Decode(&temp); err == nil {
			for _, stop := range temp.StopTimes {
				at, _ := time.Parse("15:04", stop.ArrivalTime)
				dt, _ := time.Parse("15:04", stop.DepartureTime)
				row = append(row, []interface{}{
					temp.TrainDate,
					temp.DailyTrainInfo.TrainNo,
					temp.DailyTrainInfo.Direction,
					temp.DailyTrainInfo.StartingStationID,
					temp.DailyTrainInfo.StartingStationName.ZhTw,
					temp.DailyTrainInfo.EndingStationID,
					temp.DailyTrainInfo.EndingStationName.ZhTw,
					temp.DailyTrainInfo.TrainTypeID,
					temp.DailyTrainInfo.TrainTypeCode,
					temp.DailyTrainInfo.TrainTypeName.ZhTw,
					temp.DailyTrainInfo.TripLine,
					stop.StopSequence,
					stop.StationID,
					stop.StationName.ZhTw,
					at,
					dt,
					mask(temp.DailyTrainInfo.WheelchairFlag, temp.DailyTrainInfo.PackageServiceFlag, temp.DailyTrainInfo.DiningFlag, temp.DailyTrainInfo.BikeFlag, temp.DailyTrainInfo.BreastFeedingFlag, temp.DailyTrainInfo.DailyFlag, temp.DailyTrainInfo.ServiceAddedFlag, stop.SuspendedFlag),
					temp.DailyTrainInfo.Note.ZhTw,
				})
			}
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_tra (
					train_date          date not null,
					trainno             text not null,
					direction           integer,
					starting_station_id text not null,
					starting_station_name text not null,
					ending_station_id   text not null,
					ending_station_name  text not null,
					train_type_id       text,
					train_type_code     text,
					train_type_name     text,
					tripline            integer,
					stopsequence        smallint,
					stationid           text,
					stationname         text,
					arrivaltime         time,
					departuretime       time,
					mask                smallint,
					note                text,
					updated_at          timestamp with time zone
				) ON COMMIT DROP;`
		c2 := `INSERT INTO tra_timetable (
				train_date,
				trainno,
				direction,
				starting_station_id,
				starting_station_name,
				ending_station_id,
				ending_station_name,
				train_type_id,
				train_type_code,
				train_type_name,
				tripline,
				stopsequence,
				stationid,
				stationname,
				arrivaltime,
				departuretime,
				mask,
				note,
				updated_at
			)
			SELECT train_date,trainno,direction,starting_station_id,starting_station_name,ending_station_id,ending_station_name,train_type_id,train_type_code,train_type_name,tripline,stopsequence,stationid,stationname,arrivaltime,departuretime,mask,note,NOW()
			FROM temp_tra
			ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET direction = EXCLUDED.direction, starting_station_id = EXCLUDED.starting_station_id,starting_station_name = excluded.starting_station_name,ending_station_name = excluded.ending_station_name, ending_station_id = EXCLUDED.ending_station_id,train_type_id = excluded.train_type_id, train_type_code = excluded.train_type_code, train_type_name = excluded.train_type_name, tripline = excluded.tripline, stopsequence = excluded.stopsequence, stationname = excluded.stationname, arrivaltime = excluded.arrivaltime, departuretime = excluded.departuretime, mask = excluded.mask, note = excluded.note, updated_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[RAIL] action=tra_timetable event=tx_error error=%v", err)
			return
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[RAIL] action=timetable event=create_temp_error error=%v", err)
			return
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_tra"}, []string{"train_date", "trainno", "direction", "starting_station_id", "starting_station_name", "ending_station_id", "ending_station_name", "train_type_id", "train_type_code", "train_type_name", "tripline", "stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask", "note"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, err = b.Exec(ctx, c2); err != nil {
				log.Infof("[RAIL] action=tra_timetable event=exec_error error=%v", err)
				return
			}
			if err = b.Commit(ctx); err != nil {
				log.Infof("[RAIL] action=tra_timetable event=commit_error error=%v", err)
			} else {
				log.Infof("[RAIL] action=tra_timetable event=success timetable_count=%d", len(row))
			}
		} else {
			log.Infof("[RAIL] action=tra_timetable event=copyfrom_error error=%v", err)
		}
	} else {
		log.Infof("[RAIL] action=tra_timetable event=complete reason=no_data")
	}
	log.Infof("[RAIL] action=tra_timetable event=complete")
}

func callApi(client *resty.Client, rc *redis.Client, url string, name string) (*json.Decoder, bool, error, func()) {
	since, _ := rc.Get("LastTimeGet_" + name).Result()
	resp, err := client.R().
		SetHeader("If-Modified-Since", since).
		Get(url)
	if err != nil {
		return &json.Decoder{}, false, err, nil
	}
	if resp.StatusCode() == 304 {
		err := resp.RawResponse.Body.Close()
		if err != nil {
			return &json.Decoder{}, false, err, nil
		}
		log.Infof("[RUN] action=no update=%s", name)
		return &json.Decoder{}, false, nil, nil
	}
	rc.Set("LastTimeGet_"+name, resp.Header().Get("Last-Modified"), 0)
	decorder := json.NewDecoder(resp.RawResponse.Body)
	return decorder, true, nil, func() {
		err := resp.RawResponse.Body.Close()
		if err != nil {
			log.Infof("[RUN] action=fail-close-response error=%v", err)
		}
	}
}

func getToken(rc *redis.Client) string {
	if val, err := rc.Get("TDX_Token").Result(); err == nil && val != "" {
		return val
	}
	authClient := resty.New()
	resp, err := authClient.R().
		SetHeader("content-type", "application/x-www-form-urlencoded").
		SetFormData(map[string]string{
			"grant_type":    "client_credentials",
			"client_id":     os.Getenv("TDX_CLIENT_ID"),
			"client_secret": os.Getenv("TDX_CLIENT_SECRET"),
		}).
		Post("https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token")
	if err != nil {
		log.Infof("[TDX] token fetch error: %v", err)
		return ""
	}
	var mp map[string]interface{}
	if err = json.Unmarshal(resp.Body(), &mp); err != nil {
		log.Infof("[TDX] token parse error: %v", err)
		return ""
	}
	token, ok := mp["access_token"].(string)
	if !ok || token == "" {
		log.Infof("[TDX] access_token missing from response")
		return ""
	}
	if err = rc.Set("TDX_Token", token, 6*time.Hour).Err(); err != nil {
		log.Infof("[TDX] token cache error: %v", err)
	}
	return token
}
func mask(wheel, pack, dining, bike, breast, daily, service, suspended uint8) uint16 {
	var res uint16
	days := []uint8{wheel, pack, dining, bike, breast, daily, service, suspended}
	for i, v := range days {
		if v == 1 {
			res |= 1 << i
		}
	}
	return res
}
func gettrafares(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) {
	log.Infof("[RAIL] action=get_tra_fare event=start")
	dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/TRA/ODFare"), "tra_fare")
	if err != nil || !comp {
		log.Infof("[RAIL] action=get_tra_fare event=skip reason=api_error")
		return
	}
	func() {
		defer flipopen()
		if _, err := dec.Token(); err != nil {
			log.Infof("[RAIL] action=get_tra_fare event=decode_error error=%v", err)
			return
		}
		var row [][]interface{}
		for dec.More() {
			var temp raw_trafare
			if err := dec.Decode(&temp); err == nil {
				row = append(row, []interface{}{
					temp.OriginStationID,
					temp.DestinationStationID,
					temp.TicketType,
					temp.Price,
				})
			}
		}
		if len(row) > 0 {
			c1 := `CREATE TEMP TABLE temp_tra (
					osi text,
					dsi text,
					ty text,
					p smallint
				) ON COMMIT DROP;`
			c2 := `INSERT INTO tra_fares (
					origin_station_id,
					destination_station_id,
					ticket_type,
					price,
                    updated_at
				)
				SELECT osi, dsi, ty, p,NOW() FROM temp_tra
				ON CONFLICT (origin_station_id,destination_station_id,ticket_type) DO UPDATE SET price = EXCLUDED.price,updated_at = NOW();`
			b, err := db.Begin(ctx)
			if err != nil {
				log.Infof("[rail] action=get_tra_fare event=begin_error error=%v", err)
				return
			}
			defer func(b pgx.Tx, ctx context.Context) {
				_ = b.Rollback(ctx)
			}(b, ctx)
			if _, err := b.Exec(ctx, c1); err != nil {
				log.Infof("[RAIL] action=get_tra_fare event=create_temp_error error=%v", err)
				return
			}
			_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_tra"}, []string{"osi", "dsi", "ty", "p"}, pgx.CopyFromRows(row))
			if err == nil {
				if _, execErr := b.Exec(ctx, c2); execErr != nil {
					log.Infof("[RAIL] action=get_tra_fare event=exec_error error=%v", execErr)
				}
				if commitErr := b.Commit(ctx); commitErr != nil {
					log.Infof("[rail] action=get_tra_fare event=commit_error error=%v", commitErr)
				} else {
					log.Infof("[rail] action=get_tra_fare event=success station_count=%d", len(row))
				}
			} else {
				log.Infof("[rail] action=get_tra_fare event=copyfrom_error error=%v", err)
				_ = b.Rollback(ctx)
			}
		}
	}()
	log.Infof("[rail] action=get_tra_fare event=complete")
}
