package main

import (
	"context"
	"encoding/json"
	"os"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
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

// traFarePayload reads a TRA fare from the loaded env schema and returns the
// marshaled TraFareItems proto. It returns an empty slice (not an error) when no
// rows match, so callers treat an unlanded date as NotFound (ADR-0005); it never
// fetches from TDX.
func traFarePayload(ctx context.Context, db railDB, start, end string) ([]byte, error) {
	const q = `SELECT ticket_type,price FROM tra_fares WHERE origin_station_id = $1 AND destination_station_id = $2;`
	rows, err := db.Query(ctx, q, start, end)
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
	const q = `SELECT stopsequence, stationid,stationname,arrivaltime,departuretime,mask FROM tra_timetable WHERE trainno = $1 AND train_date = $2;`
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

// traTimetablePayload reads TRA services calling at both the origin and
// destination for a date, pairs them into origin/destination legs, and returns
// the marshaled TraTimetables proto plus the number of paired legs. A zero count
// signals NotFound (ADR-0005); it never fetches from TDX.
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
// table is a caller-supplied constant ("tra_stations"/"thsr_stations").
func resolveRailStationID(ctx context.Context, db railDB, table, s string) string {
	if isNumericStationID(s) {
		return s
	}
	rows, err := db.Query(ctx,
		`SELECT station_id FROM `+table+
			` WHERE replace(name, '臺', '台') = replace($1, '臺', '台') LIMIT 1`, s)
	if err != nil {
		return s
	}
	defer rows.Close()
	if rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			return id
		}
	}
	return s
}

func traTimetablePayload(ctx context.Context, db railDB, start, end string, date time.Time) ([]byte, int, error) {
	start = resolveRailStationID(ctx, db, "tra_stations", start)
	end = resolveRailStationID(ctx, db, "tra_stations", end)
	const combined = `SELECT train_date,trainno, starting_station_id,starting_station_name,ending_station_id,ending_station_name, stopsequence,train_type_id,train_type_code,train_type_name,tripline,stationid,arrivaltime,stationname,mask,note,departuretime FROM tra_timetable WHERE stationid = ANY($1) AND train_date = $2 AND arrivaltime >= $3;`
	stations := []string{start, end}
	rows, err := db.Query(ctx, combined, stations, date.Format(time.DateOnly), date.Format(time.TimeOnly))
	if err != nil {
		return nil, 0, err
	}
	row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traTimetableRow])
	if err != nil {
		return nil, 0, err
	}
	mp := make(map[string]*models.TraTimetable)
	arr := []*models.TraTimetable{}
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
	b, err := proto.Marshal(&models.TraTimetables{Items: arr})
	if err != nil {
		return nil, 0, err
	}
	return b, len(arr), nil
}

// callApi performs a conditional TDX GET, caching the Last-Modified header so the
// next call can send If-Modified-Since. It is used by the realtime THSR
// available-seat refresh; the rail static pipeline moved to the loader (ADR-0005).
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

// getToken returns a cached TDX access token, fetching a new one when the cache
// is empty. It backs the MaaS route planner and the resty client's auth hook.
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
