package main

import (
	"context"
	"encoding/json"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

	"fmt"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// railStation decodes a TDX TRA/THSR Station element, used for both the TRA and
// THSR static station tables.
type railStation struct {
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	LocationCityCode string `json:"LocationCityCode"`
	StationPosition  struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	StationCode string `json:"StationCode"`
}

// tra_fare decodes a TDX TRA/ODFare element: fares between a station pair by
// ticket type.
type tra_fare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	Fares                []struct {
		TicketType string `json:"TicketType"`
		Price      int32  `json:"Price"`
	} `json:"Fares"`
}

// thsr_fare decodes a TDX THSR/ODFare element: fares between a station pair,
// further split by fare class and cabin class.
type thsr_fare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	Fares                []struct {
		TicketType uint8  `json:"TicketType"`
		FareClass  uint8  `json:"FareClass"`
		CabinClass uint8  `json:"CabinClass"`
		Price      uint16 `json:"Price"`
	} `json:"Fares"`
}

// traDelay decodes a TDX TRA/LiveTrainDelay element: a train's current delay in
// minutes at a station.
type traDelay struct {
	TrainNo     string `json:"TrainNo"`
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	DelayTime     uint16 `json:"DelayTime"`
	SrcUpdateTime string `json:"SrcUpdateTime"`
}

// traLiveboard decodes a TDX TRA/LiveBoard element: a train's scheduled times
// and live delay at a station, merged with LiveTrainDelay data before caching.
type traLiveboard struct {
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	TrainNo       string `json:"TrainNo"`
	Direction     bool   `json:"Direction"`
	TrainTypeID   string `json:"TrainTypeID"`
	TrainTypeCode string `json:"TrainTypeCode"`
	TrainTypeName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"TrainTypeName"`
	TripLine          uint8  `json:"TripLine"`
	EndingStationID   string `json:"EndingStationID"`
	EndingStationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"EndingStationName"`
	ScheduledArrivalTime   string `json:"ScheduledArrivalTime"`
	ScheduledDepartureTime string `json:"ScheduledDepartureTime"`
	DelayTime              uint16 `json:"DelayTime"`
	SrcUpdateTime          string `json:"SrcUpdateTime"`
}

// raw_tra_timetable decodes a TDX TRA/DailyTimetable element: one train's info
// and its ordered stop times for a given service date.
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

// raw_thsr_timetable decodes a TDX THSR/DailyTimetable element: one high-speed
// train's info and stop times for a service date. Overnight marks a train that
// crosses midnight.
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

// railTrainFlags holds a TRA train's amenity/service boolean flags (1 = set)
// before they are packed into a single bitmask by railMask.
type railTrainFlags struct {
	wheel     uint8
	pack      uint8
	dining    uint8
	bike      uint8
	breast    uint8
	daily     uint8
	service   uint8
	suspended uint8
}

// railMask packs a TRA train's amenity flags into a uint16 bitmask (bit 0 =
// wheelchair through bit 7 = suspended, in struct field order) for compact
// storage in tra_timetable.mask.
func railMask(f railTrainFlags) uint16 {
	var res uint16
	for i, v := range []uint8{f.wheel, f.pack, f.dining, f.bike, f.breast, f.daily, f.service, f.suspended} {
		if v == 1 {
			res |= 1 << i
		}
	}
	return res
}

// loadTraTimetable upserts one day's TRA daily timetable stop rows into
// tra_timetable via a temp-table COPY. Stop times parse as "15:04"; unparseable
// times become the zero time. It consumes an already-opened decoder; the
// temp_tra_timetable COPY and ON CONFLICT (train_date,trainno,stationid) upsert
// (and railMask/railTrainFlags) are byte-identical to the legacy transform.
func loadTraTimetable(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, date string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_prefetch event=decode_error date=%s error=%v", date, err)
		return err
	}
	row := [][]interface{}{}
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
					railMask(railTrainFlags{
						wheel:     temp.DailyTrainInfo.WheelchairFlag,
						pack:      temp.DailyTrainInfo.PackageServiceFlag,
						dining:    temp.DailyTrainInfo.DiningFlag,
						bike:      temp.DailyTrainInfo.BikeFlag,
						breast:    temp.DailyTrainInfo.BreastFeedingFlag,
						daily:     temp.DailyTrainInfo.DailyFlag,
						service:   temp.DailyTrainInfo.ServiceAddedFlag,
						suspended: stop.SuspendedFlag,
					}),
					temp.DailyTrainInfo.Note.ZhTw,
				})
			}
		}
	}
	if len(row) == 0 {
		log.Infof("[RAIL] action=tra_prefetch event=complete date=%s reason=no_data", date)
		return nil
	}
	c1 := `CREATE TEMP TABLE temp_tra_timetable (
				train_date            date not null,
				trainno               text not null,
				direction             integer,
				starting_station_id   text not null,
				starting_station_name text not null,
				ending_station_id     text not null,
				ending_station_name   text not null,
				train_type_id         text,
				train_type_code       text,
				train_type_name       text,
				tripline              integer,
				stopsequence          smallint,
				stationid             text,
				stationname           text,
				arrivaltime           time,
				departuretime         time,
				mask                  smallint,
				note                  text,
				updated_at            timestamp with time zone
			) ON COMMIT DROP;`
	c2 := `INSERT INTO tra_timetable (
			train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,train_type_id,train_type_code,train_type_name,
			tripline,stopsequence,stationid,stationname,arrivaltime,departuretime,mask,note,updated_at
		)
		SELECT train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,train_type_id,train_type_code,train_type_name,
			tripline,stopsequence,stationid,stationname,arrivaltime,departuretime,mask,note,NOW()
		FROM temp_tra_timetable
		ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET
			direction=EXCLUDED.direction, starting_station_id=EXCLUDED.starting_station_id,
			starting_station_name=EXCLUDED.starting_station_name, ending_station_name=EXCLUDED.ending_station_name,
			ending_station_id=EXCLUDED.ending_station_id, train_type_id=EXCLUDED.train_type_id,
			train_type_code=EXCLUDED.train_type_code, train_type_name=EXCLUDED.train_type_name,
			tripline=EXCLUDED.tripline, stopsequence=EXCLUDED.stopsequence, stationname=EXCLUDED.stationname,
			arrivaltime=EXCLUDED.arrivaltime, departuretime=EXCLUDED.departuretime,
			mask=EXCLUDED.mask, note=EXCLUDED.note, updated_at=NOW();`
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[RAIL] action=tra_prefetch event=tx_error date=%s error=%v", date, err)
		return err
	}
	defer func(b pgx.Tx, ctx context.Context) { _ = b.Rollback(ctx) }(b, ctx)
	if _, err := b.Exec(ctx, c1); err != nil {
		log.Infof("[RAIL] action=tra_prefetch event=create_temp_error date=%s error=%v", date, err)
		return err
	}
	_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_tra_timetable"}, []string{
		"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
		"ending_station_id", "ending_station_name", "train_type_id", "train_type_code", "train_type_name",
		"tripline", "stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask", "note",
	}, pgx.CopyFromRows(row))
	if err == nil {
		if _, err = b.Exec(ctx, c2); err != nil {
			log.Infof("[RAIL] action=tra_prefetch event=exec_error date=%s error=%v", date, err)
			return err
		}
		if err = b.Commit(ctx); err != nil {
			log.Infof("[RAIL] action=tra_prefetch event=commit_error date=%s error=%v", date, err)
			return err
		}
		log.Infof("[RAIL] action=tra_prefetch event=success date=%s rows=%d", date, len(row))
	} else {
		log.Infof("[RAIL] action=tra_prefetch event=copyfrom_error date=%s error=%v", date, err)
		return err
	}
	return nil
}

// loadThsrTimetable upserts one day's THSR daily timetable stop rows into
// thsr_timetable via a temp-table COPY. Stop times parse as "15:04"; unparseable
// times become the zero time. It consumes an already-opened decoder;
// the temp_thsr_timetable COPY and ON CONFLICT (train_date,trainno,stationid)
// upsert are byte-identical to the legacy transform.
func loadThsrTimetable(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, date string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_prefetch event=decode_error date=%s error=%v", date, err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp raw_thsr_timetable
		if err := dec.Decode(&temp); err == nil {
			for _, stop := range temp.StopTimes {
				// Parse "15:04" strings like the TRA path: pgx cannot binary-encode
				// a raw string into a time column during COPY.
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
					stop.StopSequence,
					stop.StationID,
					stop.StationName.ZhTw,
					at,
					dt,
					temp.DailyTrainInfo.Note.ZhTw,
					temp.DailyTrainInfo.Overnight,
				})
			}
		}
	}
	if len(row) == 0 {
		log.Infof("[RAIL] action=thsr_prefetch event=complete date=%s reason=no_data", date)
		return nil
	}
	c1 := `CREATE TEMP TABLE temp_thsr_timetable (
				train_date            date not null,
				trainno               text not null,
				direction             integer,
				starting_station_id   text not null,
				starting_station_name text not null,
				ending_station_id     text not null,
				ending_station_name   text not null,
				stopsequence          smallint,
				stationid             text,
				stationname           text,
				arrivaltime           time,
				departuretime         time,
				note                  text,
				overnight             boolean,
				updated_at            timestamp with time zone
			) ON COMMIT DROP;`
	c2 := `INSERT INTO thsr_timetable (
			train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,stopsequence,stationid,stationname,
			arrivaltime,departuretime,note,overnight,updated_at
		)
		SELECT train_date,trainno,direction,starting_station_id,starting_station_name,
			ending_station_id,ending_station_name,stopsequence,stationid,stationname,
			arrivaltime,departuretime,note,overnight,NOW()
		FROM temp_thsr_timetable
		ON CONFLICT (train_date,trainno,stationid) DO UPDATE SET
			direction=EXCLUDED.direction, starting_station_id=EXCLUDED.starting_station_id,
			starting_station_name=EXCLUDED.starting_station_name, ending_station_name=EXCLUDED.ending_station_name,
			ending_station_id=EXCLUDED.ending_station_id, stopsequence=EXCLUDED.stopsequence,
			stationname=EXCLUDED.stationname, arrivaltime=EXCLUDED.arrivaltime,
			departuretime=EXCLUDED.departuretime, note=EXCLUDED.note, overnight=EXCLUDED.overnight, updated_at=NOW();`
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[RAIL] action=thsr_prefetch event=tx_error date=%s error=%v", date, err)
		return err
	}
	defer func(b pgx.Tx, ctx context.Context) { _ = b.Rollback(ctx) }(b, ctx)
	if _, err := b.Exec(ctx, c1); err != nil {
		log.Infof("[RAIL] action=thsr_prefetch event=create_temp_error date=%s error=%v", date, err)
		return err
	}
	_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_thsr_timetable"}, []string{
		"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
		"ending_station_id", "ending_station_name", "stopsequence", "stationid", "stationname",
		"arrivaltime", "departuretime", "note", "overnight",
	}, pgx.CopyFromRows(row))
	if err == nil {
		if _, err = b.Exec(ctx, c2); err != nil {
			log.Infof("[RAIL] action=thsr_prefetch event=exec_error date=%s error=%v", date, err)
			return err
		}
		if err = b.Commit(ctx); err != nil {
			log.Infof("[RAIL] action=thsr_prefetch event=commit_error date=%s error=%v", date, err)
			return err
		}
		log.Infof("[RAIL] action=thsr_prefetch event=success date=%s rows=%d", date, len(row))
	} else {
		log.Infof("[RAIL] action=thsr_prefetch event=copyfrom_error date=%s error=%v", date, err)
		return err
	}
	return nil
}

// loadTraStation upserts TRA stations into tra_stations via a temp-table COPY,
// resolving the city from the station's LocationCityCode prefix. It consumes an
// already-opened decoder (the raw_tdx loader reconstructs it); the temp-table
// COPY and ON CONFLICT (station_id) upsert are byte-identical to the legacy
// transform. It returns the first hard error instead of logging-and-returning.
func loadTraStation(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_station event=decode_error error=%v", err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp railStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []interface{}{
				temp.StationID,
				temp.StationName.ZhTw,
				citymap2[temp.LocationCityCode],
				g,
			})
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_tra (
					station_id text,
					name text,
					city text,
					geom text
				) ON COMMIT DROP;`
		c2 := `INSERT INTO tra_stations (
					station_id,
					name,
					city,
					geom,
					updated_at
				)
				SELECT station_id, name, city, ST_GeomFromText(geom, 4326),NOW()
				FROM temp_tra
				ON CONFLICT (station_id) DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, geom = EXCLUDED.geom,updated_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[RAIL] action=tra_station event=tx_error error=%v", err)
			return err
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[RAIL] action=tra_station event=create_temp_error error=%v", err)
			return err
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_tra"}, []string{"station_id", "name", "city", "geom"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, err = b.Exec(ctx, c2); err != nil {
				log.Infof("[RAIL] action=tra_station event=exec_error error=%v", err)
				return err
			}
			if err = b.Commit(ctx); err != nil {
				log.Infof("[RAIL] action=tra_station event=commit_error error=%v", err)
				return err
			}
			log.Infof("[RAIL] action=tra_station event=success station_count=%d", len(row))
		} else {
			log.Infof("[RAIL] action=tra_station event=copyfrom_error error=%v", err)
			return err
		}
	} else {
		log.Infof("[RAIL] action=tra_station event=complete reason=no_data")
	}
	log.Infof("[RAIL] action=tra_station event=complete")
	return nil
}

// loadThsrStation upserts THSR stations into thsr_stations using a batched
// per-station INSERT (there are few HSR stations, so no temp table). It consumes
// an already-opened decoder; the INSERT ... ON CONFLICT (station_id) and
// db.SendBatch are byte-identical to the legacy transform.
func loadThsrStation(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_station event=decode_error error=%v", err)
		return err
	}
	c1 := `INSERT INTO thsr_stations (
                          station_id,
                          name,
                          city,
                          geom,
                          stationcode,
                          updated_at
                          )
			VALUES ($1, $2, $3,ST_GeomFromText($4, 4326),$5, NOW())
			ON CONFLICT (station_id) DO UPDATE SET name = EXCLUDED.name, updated_at = NOW();`
	batch := &pgx.Batch{}
	for dec.More() {
		var temp railStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			batch.Queue(c1, temp.StationID, temp.StationName.ZhTw, citymap2[temp.LocationCityCode], g, temp.StationCode)
		}
	}
	b := db.SendBatch(ctx, batch)
	_ = b.Close()
	log.Infof("[RAIL] action=thsr_station event=complete")
	return nil
}

// loadTraFare upserts the TRA OD fare table into tra_fares via a temp-table COPY,
// flattening each station pair's per-ticket-type fares into rows. It consumes an
// already-opened decoder; the temp_tra_fare COPY and ON CONFLICT
// (origin_station_id, destination_station_id, ticket_type) upsert are
// byte-identical to the legacy transform.
func loadTraFare(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_fare event=decode_error error=%v", err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp tra_fare
		if err := dec.Decode(&temp); err == nil {
			for _, t1 := range temp.Fares {
				row = append(row, []interface{}{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.Price})
			}
		}
	}
	c1 := `CREATE TEMP TABLE temp_tra_fare (
				origin_station_id text,
				destination_station_id text,
				ticket_type text,
				price int
			) ON COMMIT DROP;`
	c2 := `INSERT INTO tra_fares (
				origin_station_id,
				destination_station_id,
				ticket_type,
				price,
				updated_at
			)
			SELECT origin_station_id, destination_station_id, ticket_type, price, NOW() FROM temp_tra_fare
			ON CONFLICT (origin_station_id, destination_station_id, ticket_type)
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[RAIL] action=tra_fare event=begin_error error=%v", err)
		return err
	}
	defer func(b pgx.Tx, ctx context.Context) {
		_ = b.Rollback(ctx)
	}(b, ctx)
	_, err = b.Exec(ctx, c1)
	if err != nil {
		log.Infof("[RAIL] action=tra_fare event=execute_error error=%v", err)
		return err
	}
	_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_tra_fare"}, []string{"origin_station_id", "destination_station_id", "ticket_type", "price"}, pgx.CopyFromRows(row))
	if err == nil {
		if _, execErr := b.Exec(ctx, c2); execErr != nil {
			log.Infof("[RAIL] action=tra_fare event=exec_error error=%v", execErr)
			return execErr
		}
		if commitErr := b.Commit(ctx); commitErr != nil {
			log.Infof("[RAIL] action=tra_fare event=commit_error error=%v", commitErr)
			return commitErr
		}
		log.Infof("[RAIL] action=tra_fare event=complete row_count=%d", len(row))
	} else {
		log.Infof("[RAIL] action=tra_fare event=copyfrom_error error=%v", err)
		return err
	}
	return nil
}

// loadThsrFare upserts the THSR OD fare table into thsr_fares via a temp-table
// COPY, keyed by station pair plus ticket/fare/cabin class. It consumes an
// already-opened decoder; the temp_thsr COPY and ON CONFLICT
// (origin,destination,ticket_type,fare_class,cabin_class) upsert are
// byte-identical to the legacy transform.
func loadThsrFare(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_fare event=decode_error error=%v", err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp thsr_fare
		if err := dec.Decode(&temp); err == nil {
			for _, t1 := range temp.Fares {
				row = append(row, []interface{}{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.FareClass, t1.CabinClass, t1.Price})
			}
		}
	}
	c1 := `CREATE TEMP TABLE temp_thsr (
				origin_station_id text,
				destination_station_id text,
				ticket_type smallint,
				fare_class smallint,
				cabin_class smallint,
				price int
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
			SELECT origin_station_id, destination_station_id, ticket_type, fare_class,cabin_class,price, NOW() FROM temp_thsr
			ON CONFLICT (origin_station_id, destination_station_id, ticket_type, fare_class, cabin_class)
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[RAIL] action=thsr_fare event=begin_error error=%v", err)
		return err
	}
	defer func(b pgx.Tx, ctx context.Context) {
		_ = b.Rollback(ctx)
	}(b, ctx)
	_, err = b.Exec(ctx, c1)
	if err != nil {
		log.Infof("[RAIL] action=thsr_fare event=execute_error error=%v", err)
		return err
	}
	_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_thsr"}, []string{"origin_station_id", "destination_station_id", "ticket_type", "fare_class", "cabin_class", "price"}, pgx.CopyFromRows(row))
	if err == nil {
		if _, execErr := b.Exec(ctx, c2); execErr != nil {
			log.Infof("[RAIL] action=thsr_fare event=exec_error error=%v", execErr)
			return execErr
		}
		if commitErr := b.Commit(ctx); commitErr != nil {
			log.Infof("[RAIL] action=thsr_fare event=commit_error error=%v", commitErr)
			return commitErr
		}
		log.Infof("[RAIL] action=thsr_fare event=complete row_count=%d", len(row))
	} else {
		log.Infof("[RAIL] action=thsr_fare event=copyfrom_error error=%v", err)
		return err
	}
	return nil
}

// traEta refreshes TRA realtime data into Redis on the 2-minute cron. It caches
// per-train delays (hash tra:delay plus a published tra:delay:all snapshot), then
// builds per-station live boards, merging in those delays, and caches each under
// tra:liveboard:<stationID>. All cached values carry a 3-minute TTL so stale data
// expires. A missing delay feed is logged but does not block the live board.
func traEta(ctx context.Context, fetch boundFetch, sink liveSink, rc *redis.Client) {
	log.Infof("[TRA_ETA] action=tra_eta event=start")
	dec, comp, flipopen, err := fetch(ctx, "/v2/Rail/TRA/LiveTrainDelay", "tra_delay")
	if err == nil && comp {
		func() {
			defer flipopen()
			if _, err := dec.Token(); err == nil {
				data := &models.TraDelays{
					Delay: make(map[string]int32),
				}
				count := 0
				pipe := sink.pipeline()
				for dec.More() {
					var temp traDelay
					if err := dec.Decode(&temp); err == nil {
						count++
						data.Delay[temp.TrainNo] = int32(temp.DelayTime)
						pipe.HSet(shared.TraDelayHashKey, temp.TrainNo, temp.DelayTime)
					}
				}
				bytes, _ := proto.Marshal(data)
				pipe.Set(shared.TraDelayAllKey, bytes, 3*time.Minute)
				pipe.Publish(shared.TraDelayAllKey, string(bytes))
				pipe.Expire(shared.TraDelayHashKey, 3*time.Minute)
				pipErr := pipe.Exec()
				if pipErr != nil {
					log.Infof("[TRA_ETA] action=tra_eta event=delay_redis_error error=%v", pipErr)
				} else {
					log.Infof("[TRA_ETA] action=tra_eta event=delay_redis_success count=%d", count)
				}
			}
		}()
	} else {
		// On a 304, boundFetch has already re-armed the delay keys' TTL.
		log.Infof("[TRA_ETA] action=tra_eta event=skip_delay reason=api_error")
	}
	dec, comp, flipopen, err = fetch(ctx, "/v2/Rail/TRA/LiveBoard", "tra_liveboard")
	func() {
		if flipopen != nil {
			defer flipopen()
		}
		if err != nil || !comp {
			return
		}
		if _, err := dec.Token(); err != nil {
			return
		}
		delays, _ := rc.HGetAll(shared.TraDelayHashKey).Result()
		res := make(map[string][]*models.Tra_LiveBoard)
		for dec.More() {
			var temp traLiveboard
			if err := dec.Decode(&temp); err == nil {
				if delay, ok := delays[temp.TrainNo]; ok {
					var inter uint16
					if _, err := fmt.Sscanf(delay, "%d", &inter); err == nil {
						temp.DelayTime = inter
					}
				}
				pb := &models.Tra_LiveBoard{
					TrainNo:                temp.TrainNo,
					Direction:              temp.Direction,
					TrainTypeId:            temp.TrainTypeID,
					TrainTypeCode:          temp.TrainTypeCode,
					TrainTypeName:          temp.TrainTypeName.ZhTw,
					EndingStationId:        temp.EndingStationID,
					EndingStationName:      temp.EndingStationName.ZhTw,
					ScheduledArrivalTime:   temp.ScheduledArrivalTime,
					ScheduledDepartureTime: temp.ScheduledDepartureTime,
					Delay:                  int32(temp.DelayTime),
					TripLine:               int32(temp.TripLine),
				}
				res[temp.StationID] = append(res[temp.StationID], pb)
			}
		}
		pipe := sink.pipeline()
		for a, b := range res {
			pb := &models.Tra_LiveBoards{
				StationId: a,
				Items:     b,
			}
			pbs, err := proto.Marshal(pb)
			if err != nil {
				continue
			}
			pipe.Set(shared.TraLiveboardKey(a), pbs, 3*time.Minute)
		}
		_ = pipe.Exec()
	}()
	log.Infof("[TRA_ETA] action=tra_eta event=complete")
}
