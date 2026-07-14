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
func loadTraTimetable(ctx context.Context, dec *json.Decoder, sink loadSink, date string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_prefetch event=decode_error date=%s error=%v", date, err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp raw_tra_timetable
		if err := dec.Decode(&temp); err == nil {
			// datasetJSON strips the traindate partition column from every
			// reconstructed element, so TrainDate decodes empty; the partition
			// value is that date by definition.
			if temp.TrainDate == "" {
				temp.TrainDate = date
			}
			for _, stop := range temp.StopTimes {
				at, _ := time.Parse("15:04", stop.ArrivalTime)
				dt, _ := time.Parse("15:04", stop.DepartureTime)
				row = append(row, []any{
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
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "tra_timetable",
		createSQL: `CREATE TEMP TABLE temp_tra_timetable (
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
			) ON COMMIT DROP;`,
		tempTable: "temp_tra_timetable",
		copyCols: []string{
			"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
			"ending_station_id", "ending_station_name", "train_type_id", "train_type_code", "train_type_name",
			"tripline", "stopsequence", "stationid", "stationname", "arrivaltime", "departuretime", "mask", "note",
		},
		insertSQL: `INSERT INTO tra_timetable (
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
			mask=EXCLUDED.mask, note=EXCLUDED.note, updated_at=NOW();`,
	}, row)
}

// loadThsrTimetable upserts one day's THSR daily timetable stop rows into
// thsr_timetable via a temp-table COPY. Stop times parse as "15:04"; unparseable
// times become the zero time. It consumes an already-opened decoder;
// the temp_thsr_timetable COPY and ON CONFLICT (train_date,trainno,stationid)
// upsert are byte-identical to the legacy transform.
func loadThsrTimetable(ctx context.Context, dec *json.Decoder, sink loadSink, date string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_prefetch event=decode_error date=%s error=%v", date, err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp raw_thsr_timetable
		if err := dec.Decode(&temp); err == nil {
			for _, stop := range temp.StopTimes {
				// Parse "15:04" strings like the TRA path: pgx cannot binary-encode
				// a raw string into a time column during COPY.
				at, _ := time.Parse("15:04", stop.ArrivalTime)
				dt, _ := time.Parse("15:04", stop.DepartureTime)
				row = append(row, []any{
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
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "thsr_timetable",
		createSQL: `CREATE TEMP TABLE temp_thsr_timetable (
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
			) ON COMMIT DROP;`,
		tempTable: "temp_thsr_timetable",
		copyCols: []string{
			"train_date", "trainno", "direction", "starting_station_id", "starting_station_name",
			"ending_station_id", "ending_station_name", "stopsequence", "stationid", "stationname",
			"arrivaltime", "departuretime", "note", "overnight",
		},
		insertSQL: `INSERT INTO thsr_timetable (
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
			departuretime=EXCLUDED.departuretime, note=EXCLUDED.note, overnight=EXCLUDED.overnight, updated_at=NOW();`,
	}, row)
}

// loadTraStation upserts TRA stations into tra_stations via a temp-table COPY,
// resolving the city from the station's LocationCityCode prefix. It consumes an
// already-opened decoder (the raw_tdx loader reconstructs it); the temp-table
// COPY and ON CONFLICT (station_id) upsert are byte-identical to the legacy
// transform. It returns the first hard error instead of logging-and-returning.
func loadTraStation(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_station event=decode_error error=%v", err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp railStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []any{
				temp.StationID,
				temp.StationName.ZhTw,
				citymap2[temp.LocationCityCode],
				g,
			})
		}
	}
	if len(row) > 0 {
		if err := sink.copyUpsert(ctx, copyUpsertSpec{
			key: "tra_station",
			createSQL: `CREATE TEMP TABLE temp_tra (
					station_id text,
					name text,
					city text,
					geom text
				) ON COMMIT DROP;`,
			tempTable: "temp_tra",
			copyCols:  []string{"station_id", "name", "city", "geom"},
			insertSQL: `INSERT INTO tra_stations (
					station_id,
					name,
					city,
					geom,
					updated_at
				)
				SELECT station_id, name, city, ST_GeomFromText(geom, 4326),NOW()
				FROM temp_tra
				ON CONFLICT (station_id) DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, geom = EXCLUDED.geom,updated_at = NOW();`,
		}, row); err != nil {
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
func loadTraFare(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=tra_fare event=decode_error error=%v", err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp tra_fare
		if err := dec.Decode(&temp); err == nil {
			for _, t1 := range temp.Fares {
				row = append(row, []any{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.Price})
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "tra_fare",
		createSQL: `CREATE TEMP TABLE temp_tra_fare (
				origin_station_id text,
				destination_station_id text,
				ticket_type text,
				price int
			) ON COMMIT DROP;`,
		tempTable: "temp_tra_fare",
		copyCols:  []string{"origin_station_id", "destination_station_id", "ticket_type", "price"},
		insertSQL: `INSERT INTO tra_fares (
				origin_station_id,
				destination_station_id,
				ticket_type,
				price,
				updated_at
			)
			SELECT origin_station_id, destination_station_id, ticket_type, price, NOW() FROM temp_tra_fare
			ON CONFLICT (origin_station_id, destination_station_id, ticket_type)
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`,
	}, row)
}

// loadThsrFare upserts the THSR OD fare table into thsr_fares via a temp-table
// COPY, keyed by station pair plus ticket/fare/cabin class. It consumes an
// already-opened decoder; the temp_thsr COPY and ON CONFLICT
// (origin,destination,ticket_type,fare_class,cabin_class) upsert are
// byte-identical to the legacy transform.
func loadThsrFare(ctx context.Context, dec *json.Decoder, sink loadSink, _ string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[RAIL] action=thsr_fare event=decode_error error=%v", err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp thsr_fare
		if err := dec.Decode(&temp); err == nil {
			for _, t1 := range temp.Fares {
				row = append(row, []any{temp.OriginStationID, temp.DestinationStationID, t1.TicketType, t1.FareClass, t1.CabinClass, t1.Price})
			}
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "thsr_fare",
		createSQL: `CREATE TEMP TABLE temp_thsr (
				origin_station_id text,
				destination_station_id text,
				ticket_type smallint,
				fare_class smallint,
				cabin_class smallint,
				price int
			) ON COMMIT DROP;`,
		tempTable: "temp_thsr",
		copyCols:  []string{"origin_station_id", "destination_station_id", "ticket_type", "fare_class", "cabin_class", "price"},
		insertSQL: `INSERT INTO thsr_fares (
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
			DO UPDATE SET price = EXCLUDED.price, updated_at = NOW()`,
	}, row)
}

// traEta refreshes TRA realtime data into Redis on the 2-minute cron: per-train
// delays as hash tra:delay plus a published tra:delay:all snapshot, all with a
// 3-minute TTL so stale data expires.
func traEta(ctx context.Context, fetch boundFetch, sink liveSink) error {
	log.Infof("[TRA_ETA] action=tra_eta event=start")
	result, err := fetch(ctx, "/v2/Rail/TRA/LiveTrainDelay", "tra_delay")
	if err != nil {
		log.Infof("[TRA_ETA] action=tra_eta event=skip_delay reason=api_error error=%v", err)
		return err
	}
	if !result.Modified {
		// On a 304, boundFetch has already re-armed the delay keys' TTL.
		log.Infof("[TRA_ETA] action=tra_eta event=skip_delay reason=no_update")
		return nil
	}
	err = commitTDXFetch(result, func(dec *json.Decoder) error {
		data := &models.TraDelays{
			Delay: make(map[string]int32),
		}
		count := 0
		pipe := sink.pipeline()
		if decErr := decodeLiveItems(dec, func(temp traDelay) error {
			count++
			data.Delay[temp.TrainNo] = int32(temp.DelayTime)
			pipe.HSet(shared.TraDelayHashKey, temp.TrainNo, temp.DelayTime)
			return nil
		}); decErr != nil {
			return decErr
		}
		bytes, err := proto.Marshal(data)
		if err != nil {
			return err
		}
		pipe.Set(shared.TraDelayAllKey, bytes, traLiveTTL)
		pipe.Publish(shared.TraDelayAllKey, string(bytes))
		pipe.Expire(shared.TraDelayHashKey, traLiveTTL)
		if err := pipe.Exec(); err != nil {
			return err
		}
		log.Infof("[TRA_ETA] action=tra_eta event=delay_redis_success count=%d", count)
		return nil
	})
	if err != nil {
		log.Infof("[TRA_ETA] action=tra_eta event=process_error error=%v", err)
		return err
	}
	log.Infof("[TRA_ETA] action=tra_eta event=complete")
	return nil
}
