package main

import (
	"context"
	"encoding/json"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

	"fmt"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"google.golang.org/protobuf/proto"
)

// mrtStation decodes a TDX Rail/Metro/Station element used for the metro static
// station table. serviceType is unexported and not populated from JSON.
type mrtStation struct {
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	LocationCity       string `json:"LocationCity"`
	serviceType        string
	StationID          string `json:"StationID"`
	BikeAllowOnHoliday bool   `json:"BikeAllowOnHoliday"`
	StationName        struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
}

// mrtFirstlast decodes a TDX Rail/Metro/FirstLastTimetable element: first/last
// train times per station, line, and destination for a weekly service pattern.
type mrtFirstlast struct {
	LineID                 string `json:"LineID"`
	StationID              string `json:"StationID"`
	TripHeadSign           string `json:"TripHeadSign"`
	city                   string
	DestinationStaionID    string `json:"DestinationStaionID"`
	DestinationStationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"DestinationStationName"`
	FirstTrainTime string `json:"FirstTrainTime"`
	LastTrainTime  string `json:"LastTrainTime"`
	ServiceDay     struct {
		Monday           bool `json:"Monday"`
		Tuesday          bool `json:"Tuesday"`
		Wednesday        bool `json:"Wednesday"`
		Thursday         bool `json:"Thursday"`
		Friday           bool `json:"Friday"`
		Saturday         bool `json:"Saturday"`
		Sunday           bool `json:"Sunday"`
		NationalHolidays bool `json:"NationalHolidays"`
	} `json:"ServiceDay"`
}

// mrtLive decodes a TDX Rail/Metro/LiveBoard element: the live estimate for a
// train approaching a station toward a destination.
type mrtLive struct {
	LineID                 string `json:"LineID"`
	StationID              string `json:"StationID"`
	TripHeadSign           string `json:"TripHeadSign"`
	city                   string
	DestinationStaionID    string `json:"DestinationStaionID"`
	DestinationStationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"DestinationStationName"`
	ServiceStatus uint8 `json:"ServiceStatus"`
	EstimateTime  int32 `json:"EstimateTime"`
}

// mrtStatic is the daily static-ingestion entry point for metro: stations and
// first/last timetables. It always returns nil. The OD fare matrix is loaded
// separately from raw_tdx by loadMrtJourneyMatrix (loader registry key
// "mrt_odfare"), so this job no longer fetches it directly.
func mrtStatic(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) error {
	log.Infof("[MRT] action=mrt_static event=start")
	getmrtStation(ctx, client, rc, db)
	getmrtFirstlast(ctx, client, rc, db)
	log.Infof("[MRT] action=mrt_static event=complete")
	return nil
}

// getmrtStation upserts metro stations into mrt_station for each metro system
// via a per-system temp-table COPY then ON CONFLICT upsert on (station_id,
// system). Per-system failures are logged and skipped.
func getmrtStation(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) {
	log.Infof("[MRT] action=getmrt_station event=start")
	var systems = []string{"TRTC", "KRTC", "KLRT", "TYMC", "NTMC"}
	for _, system := range systems {
		log.Infof("[MRT] action=getmrt_station system=%s event=system_start", system)
		dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/Metro/Station/%s", system), "mrt_stations"+system)
		if err != nil || !comp {
			log.Infof("[MRT] action=getmrt_station system=%s event=skip reason=api_error", system)
			continue
		}
		func() {
			defer flipopen()
			if loadErr := loadMrtStations(ctx, dec, db, rc, system); loadErr != nil {
				log.Infof("[MRT] action=getmrt_station system=%s event=error error=%v", system, loadErr)
			}
		}()
	}
	log.Infof("[MRT] action=getmrt_station event=complete")
}

// loadMrtStations upserts one metro system's stations into mrt_station via a
// temp-table COPY then ON CONFLICT (station_id, system) upsert. It consumes an
// already-opened decoder; the temp_mrt COPY and upsert are byte-identical to the
// legacy transform.
func loadMrtStations(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, system string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[MRT] action=getmrt_station system=%s event=decode_error error=%v", system, err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp mrtStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []interface{}{
				g,
				system,
				temp.StationName.ZhTw,
				temp.LocationCity,
				temp.StationID,
				temp.BikeAllowOnHoliday,
			})
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_mrt (
					geom text,
					system text,
					name text,
					city text,
					id text,
					bike bool
				) ON COMMIT DROP;`
		c2 := `INSERT INTO mrt_station (
					stationposition,
					system,
					name,
					city,
					station_id,
					bikeallowonholiday,
					updated_at
				)
				SELECT st_geomfromtext(geom, 4326), system, name, city,id, bike,NOW() FROM temp_mrt
				ON CONFLICT (station_id,system) DO UPDATE SET name = EXCLUDED.name,city = excluded.city,stationposition = EXCLUDED.stationposition,updated_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[MRT] action=getmrt_station system=%s event=begin_error error=%v", system, err)
			return err
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[MRT] action=getmrt_station system=%s event=create_temp_error error=%v", system, err)
			return err
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_mrt"}, []string{"geom", "system", "name", "city", "id", "bike"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, execErr := b.Exec(ctx, c2); execErr != nil {
				log.Infof("[MRT] action=getmrt_station system=%s event=exec_error error=%v", system, execErr)
			}
			if commitErr := b.Commit(ctx); commitErr != nil {
				log.Infof("[MRT] action=getmrt_station system=%s event=commit_error error=%v", system, commitErr)
				return commitErr
			}
			log.Infof("[MRT] action=getmrt_station system=%s event=success station_count=%d", system, len(row))
		} else {
			log.Infof("[MRT] action=getmrt_station system=%s event=copyfrom_error error=%v", system, err)
			_ = b.Rollback(ctx)
			return err
		}
	}
	return nil
}

// getmrtFirstlast rebuilds mrt_schedule (first/last train times) per metro
// system via temp-table COPY and upsert, then prunes rows older than this run's
// start so retired schedule entries drop out. NTMC is excluded (no first/last
// feed). Per-system failures are logged and skipped.
func getmrtFirstlast(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) {
	log.Infof("[MRT] action=getmrt_firstlast event=start")
	var systems = []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	for _, system := range systems {
		log.Infof("[MRT] action=getmrt_firstlast system=%s event=system_start", system)
		dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/Metro/FirstLastTimetable/%s", system), "mrt_firstlast"+system)
		if err != nil || !comp {
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=skip reason=api_error", system)
			continue
		}
		func() {
			defer flipopen()
			if loadErr := loadMrtFirstlast(ctx, dec, db, rc, system); loadErr != nil {
				log.Infof("[MRT] action=getmrt_firstlast system=%s event=error error=%v", system, loadErr)
			}
		}()
	}
	log.Infof("[MRT] action=getmrt_firstlast event=complete")
}

// loadMrtFirstlast rebuilds mrt_schedule (first/last train times) for one metro
// system as partition-replace: within ONE transaction it DELETEs the system's
// rows, COPYs the fresh rows into temp_mrt, then plain-INSERTs them with no
// DISTINCT ON and no ON CONFLICT. The natural key (station_id, lineid,
// destinationstaionid, serviceday, system) is not unique in real data, so every
// raw row must survive rather than be collapsed. It consumes an already-opened
// decoder. updated_at is stamped NOW() so the freshness probe (main.go's
// MAX(updated_at) per system) keeps working.
func loadMrtFirstlast(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, system string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[MRT] action=getmrt_firstlast system=%s event=decode_error error=%v", system, err)
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp mrtFirstlast
		if err := dec.Decode(&temp); err == nil {
			row = append(row, []interface{}{
				temp.StationID,
				temp.LineID,
				temp.TripHeadSign,
				temp.DestinationStaionID,
				temp.DestinationStationName.ZhTw,
				temp.FirstTrainTime,
				temp.LastTrainTime,
				mask(temp.ServiceDay.Monday, temp.ServiceDay.Tuesday, temp.ServiceDay.Wednesday, temp.ServiceDay.Thursday, temp.ServiceDay.Friday, temp.ServiceDay.Saturday, temp.ServiceDay.Sunday, temp.ServiceDay.NationalHolidays),
				system,
			})
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_mrt (
                               id text,
                               lid text,
							   sign text,
                               dsid text,
                               dsname text,
                               ft text,
                               lt text,
       						   mask int2,
       						   sys text
					) ON COMMIT DROP;`
		c2 := `INSERT INTO mrt_schedule (
						station_id,
						lineid,
						destinationstaionid,
						destinationstationname,
						firsttraintime,
						lasttraintime,
						serviceday,
						system,
						created_at,
						updated_at,
						trip_head_sign
					)
					SELECT id,lid, dsid, dsname, ft, lt,mask,sys,NOW(),NOW(),sign FROM temp_mrt`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=begin_error error=%v", system, err)
			return err
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, `DELETE FROM mrt_schedule WHERE system = $1`, system); err != nil {
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=delete_partition_error error=%v", system, err)
			return err
		}
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=create_temp_error error=%v", system, err)
			return err
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_mrt"}, []string{"id", "lid", "sign", "dsid", "dsname", "ft", "lt", "mask", "sys"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, execErr := b.Exec(ctx, c2); execErr != nil {
				log.Infof("[MRT] action=getmrt_firstlast system=%s event=exec_error error=%v", system, execErr)
			}
			if commitErr := b.Commit(ctx); commitErr != nil {
				log.Infof("[MRT] action=getmrt_firstlast system=%s event=commit_error error=%v", system, commitErr)
				return commitErr
			}
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=success row_count=%d", system, len(row))
		} else {
			log.Infof("[MRT] action=getmrt_firstlast system=%s event=copyfrom_error error=%v", system, err)
			_ = b.Rollback(ctx)
			return err
		}
	}
	return nil
}

// mrtEta refreshes live metro arrivals into Redis on the 10s cron. Per system it
// pipelines a protobuf MrtLive per (station, line) under mrt_live:... with a
// 2-minute TTL and publishes per-station updates for live streaming. NTMC is
// excluded (no live board). Per-system failures are logged and skipped.
func mrtEta(client *resty.Client, rc *redis.Client) {
	log.Infof("[MRT_ETA] action=mrt_eta event=start")
	var systems = []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	for _, system := range systems {
		log.Infof("[MRT_ETA] action=mrt_eta system=%s event=system_start", system)
		dec, comp, err, flipopen := callApi(client, rc, fmt.Sprintf("/v2/Rail/Metro/LiveBoard/%s", system), "mrt_LiveBoard"+system)
		if !comp {
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=skip reason=no updated", system)
			continue
		}
		if err != nil {
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=skip reason=api_error", system)
			continue
		}
		if _, err := dec.Token(); err != nil {
			flipopen()
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=decode_error error=%v", system, err)
			continue
		}
		func() {
			defer flipopen()
			pipe := rc.Pipeline()
			for dec.More() {
				var temp mrtLive
				if err := dec.Decode(&temp); err == nil {
					raw := &models.MrtLive{
						LineID:                 temp.LineID,
						StationID:              temp.StationID,
						System:                 system,
						TripHeadSign:           temp.TripHeadSign,
						DestinationStaionID:    temp.DestinationStaionID,
						DestinationStationName: temp.DestinationStationName.ZhTw,
						ServiceStatus:          int32(temp.ServiceStatus),
						EstimateTime:           temp.EstimateTime,
					}
					pb, err := proto.Marshal(raw)
					if err != nil {
						continue
					}
					pipe.Set(fmt.Sprintf("mrt_live:%s:%s:%s", system, temp.StationID, temp.LineID), pb, 2*time.Minute)
					pipe.Publish(fmt.Sprintf("mrt_live:%s:%s", system, temp.StationID), string(pb))
				}
			}
			_, _ = pipe.Exec()
		}()
	}
	log.Infof("[MRT_ETA] action=mrt_eta event=complete")
}

// mrtODFare decodes a TDX Rail/Metro/ODFare element: fares between an
// origin/destination station pair, by ticket type.
type mrtODFare struct {
	OriginStationID      string `json:"OriginStationID"`
	DestinationStationID string `json:"DestinationStationID"`
	Fares                []struct {
		TicketType int `json:"TicketType"`
		Price      int `json:"Price"`
	} `json:"Fares"`
}

// loadMrtJourneyMatrix upserts one metro system's OD fare matrix into
// mrt_journey_matrix from a decoder over the reconstructed raw_tdx array. It
// decodes []mrtODFare and upserts the adult fare (TicketType 1) per OD pair.
// This is the sole writer of mrt_journey_matrix (loader registry key
// "mrt_odfare"); the table carries fares only.
func loadMrtJourneyMatrix(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, system string) error {
	var fares []mrtODFare
	if err := dec.Decode(&fares); err != nil {
		log.Infof("[MRT] action=mrt_journey_matrix system=%s event=decode_error error=%v", system, err)
		return err
	}
	batch := &pgx.Batch{}
	for _, f := range fares {
		adultPrice := 0
		for _, t := range f.Fares {
			if t.TicketType == 1 {
				adultPrice = t.Price
			}
		}
		id := fmt.Sprintf("%s-%s-%s", system, f.OriginStationID, f.DestinationStationID)
		batch.Queue(`
					INSERT INTO mrt_journey_matrix
						(id, from_station_id, to_station_id, system, fare_nt, updated_at)
					VALUES ($1,$2,$3,$4,$5,NOW())
					ON CONFLICT (from_station_id, to_station_id, system)
					DO UPDATE SET fare_nt=EXCLUDED.fare_nt, updated_at=NOW()`,
			id, f.OriginStationID, f.DestinationStationID, system, adultPrice,
		)
	}
	br := db.SendBatch(ctx, batch)
	if err := br.Close(); err != nil {
		return fmt.Errorf("mrt journey matrix batch %s: %w", system, err)
	}
	log.Infof("[MRT] journey matrix upserted %d rows for %s", len(fares), system)
	return nil
}
