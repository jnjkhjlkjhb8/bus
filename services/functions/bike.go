package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// bikeStation is the subset of a TDX Bike/Station record used for the static
// station table (identity, name, coordinates, capacity).
type bikeStation struct {
	StationUID  string `json:"StationUID"`
	StationID   string `json:"StationID"`
	StationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	StationAddress struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationAddress"`
	BikesCapacity uint8 `json:"BikesCapacity"`
	ServiceType   uint8 `json:"ServiceType"`
}

// bikeAvailability is the subset of a TDX Bike/Availability record used for the
// realtime bike ETA cache (live rentable/returnable counts per station).
type bikeAvailability struct {
	StationUID               string `json:"StationUID"`
	StationID                string `json:"StationID"`
	ServiceStatus            uint8  `json:"ServiceStatus"`
	ServiceType              uint8  `json:"ServiceType"`
	AvailableReturnBikes     uint8  `json:"AvailableReturnBikes"`
	AvailableRentBikesDetail struct {
		GeneralBikes  uint8 `json:"GeneralBikes"`
		ElectricBikes uint8 `json:"ElectricBikes"`
	} `json:"AvailableRentBikesDetail"`
}

// bikeStatic is the daily static-ingestion entry point for bike-share stations.
// It always returns nil; failures are logged per-city inside getbikeStation so
// one city's error does not fail the whole daily run.
func bikeStatic(ctx context.Context, tdx *shared.TDXClient, rc *redis.Client, db *pgxpool.Pool) error {
	log.Infof("[BIKE] action=bike_static event=start")
	getbikeStation(ctx, tdx, rc, db)
	log.Infof("[BIKE] action=bike_static event=complete")
	return nil
}

// getbikeStation upserts bike-share stations into bike_stations, city by city,
// via a per-city temp-table COPY then ON CONFLICT upsert. Cities with no public
// bike-share feed are skipped (the inline list mirrors ingestBikeSkip). The
// "YouBike2.0_" name prefix is stripped before storing.
func getbikeStation(ctx context.Context, tdx *shared.TDXClient, rc *redis.Client, db *pgxpool.Pool) {
	log.Infof("[BIKE] action=getbike_station event=start")
	for _, city := range cities {
		if city == "Keelung" || city == "HsinchuCounty" || city == "NantouCounty" || city == "YilanCounty" || city == "PenghuCounty" || city == "KinmenCounty" || city == "LienchiangCounty" || city == "InterCity" || city == "HualienCounty" {
			continue
		}
		log.Infof("[BIKE] action=getbike_station city=%s event=city_start", city)
		dec, comp, flipopen, err := tdx.Get(fmt.Sprintf("/v2/Bike/Station/City/%s", city), "bike_stations"+city)
		func() {
			if flipopen != nil {
				defer flipopen()
			}
			if err != nil || !comp {
				log.Infof("[BIKE] action=getbike_station city=%s event=skip reason=api_error=%s", city, err)
				return
			}
			if loadErr := loadBikeStations(ctx, dec, db, rc, city); loadErr != nil {
				log.Infof("[BIKE] action=getbike_station city=%s event=error error=%v", city, loadErr)
			}
		}()
	}
	log.Infof("[BIKE] action=getbike_station event=complete")
}

// loadBikeStations upserts one city's bike-share stations into bike_stations via
// a temp-table COPY then ON CONFLICT (station_uid) upsert. It consumes an
// already-opened decoder; the "YouBike2.0_" prefix strip, ST_GeomFromText, and
// the temp_bike COPY/upsert are byte-identical to the legacy transform. part is
// the partition value, which for this dataset is the city.
func loadBikeStations(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, city string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[BIKE] action=getbike_station city=%s event=decode_error error=%v", city, err.Error())
		return err
	}
	row := [][]interface{}{}
	for dec.More() {
		var temp bikeStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []interface{}{
				temp.StationUID,
				temp.StationID,
				strings.TrimPrefix(temp.StationName.ZhTw, "YouBike2.0_"),
				temp.BikesCapacity,
				temp.ServiceType,
				city,
				g,
				temp.StationAddress.ZhTw,
			})
		}
	}
	if len(row) > 0 {
		c1 := `CREATE TEMP TABLE temp_bike (
                            uid text,
                            id text,
                            name text,
                            cap int,
                            type int,
							city text,
                            geom text,
                            addr text
					) ON COMMIT DROP`
		c2 := `INSERT INTO bike_stations (
                           station_uid,
                           station_id,
                           name,
                           capacity,
                           service_type,
						   city,
                           geom,
                           address,
                           updated_at
					)
					SELECT uid, id, name, cap, type, city,st_geomfromtext(geom, 4326) AS temp, addr AS address,NOW() FROM temp_bike 
					ON CONFLICT (station_uid) DO UPDATE SET name = EXCLUDED.name,capacity = EXCLUDED.capacity,service_type = EXCLUDED.service_type,city = excluded.city,geom = EXCLUDED.geom,address = EXCLUDED.address,updated_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infoln(err.Error())
			return err
		}
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[BIKE] action=getbike_station city=%s event=create_temp_error error=%v", city, err)
			return err
		}
		_, err = b.CopyFrom(ctx, pgx.Identifier{"temp_bike"}, []string{"uid", "id", "name", "cap", "type", "city", "geom", "addr"}, pgx.CopyFromRows(row))
		if err == nil {
			if _, execErr := b.Exec(ctx, c2); execErr != nil {
				log.Infof("[BIKE] action=getbike_station city=%s event=exec_error error=%v", city, execErr)
			}
			if commitErr := b.Commit(ctx); commitErr != nil {
				log.Infof("[BIKE] action=getbike_station city=%s event=commit_error error=%v", city, commitErr)
				return commitErr
			}
			log.Infof("[BIKE] action=getbike_station city=%s event=success station_count=%d", city, len(row))
		} else {
			log.Infof("[BIKE] action=getbike_station city=%s event=copyfrom_error error=%v", city, err)
			_ = b.Rollback(ctx)
			return err
		}
	}
	return nil
}

// bikeHistorySampleGate is the process-wide 5-minute-per-station gate shared
// across bikeEta rounds, so history sampling survives between 30s ticks.
var bikeHistorySampleGate bikeHistorySampler

// bikeEta refreshes live bike availability into Redis every 30s. For each
// non-skipped city it fetches TDX Bike/Availability and pipelines a protobuf
// BikeEta per station under bike_availability:<StationUID> with a 2-minute TTL,
// so stale data expires if a city stops updating. Alongside the Redis refresh it
// samples each station's rentable/returnable counts into
// bike_availability_history at most once per 5 minutes per station
// (bikeHistorySampleGate), building the training data for future availability
// prediction. A nil db skips history collection so the realtime path can run
// without a database.
func bikeEta(ctx context.Context, fetch boundFetch, sink liveSink, db *pgxpool.Pool) {
	log.Infof("[BIKE_ETA] action=bike_eta event=start")
	now := time.Now()
	var historyRows [][]interface{}
	for _, city := range cities {
		if city == "Keelung" || city == "HsinchuCounty" || city == "NantouCounty" || city == "YilanCounty" || city == "PenghuCounty" || city == "KinmenCounty" || city == "LienchiangCounty" || city == "InterCity" || city == "HualienCounty" {
			continue
		}
		log.Infof("[BIKE_ETA] action=bike_eta city=%s event=city_start", city)
		dec, comp, flipopen, err := fetch(ctx, fmt.Sprintf("/v2/Bike/Availability/City/%s", city), "bike_availability"+city)
		if !comp {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=skip reason=no updated", city)
			continue
		}
		if err != nil {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=skip reason=api_error,error=%s", city, err)
			continue
		}
		if _, err := dec.Token(); err != nil {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=decode_error error=%v", city, err)
			continue
		}
		func() {
			defer flipopen()
			pipe := sink.pipeline()
			for dec.More() {
				var temp bikeAvailability
				if err := dec.Decode(&temp); err == nil {
					availableRent := int(temp.AvailableRentBikesDetail.GeneralBikes) + int(temp.AvailableRentBikesDetail.ElectricBikes)
					raw := &models.BikeEta{
						StationUID:           temp.StationUID,
						ServiceStatus:        int32(temp.ServiceStatus),
						ServiceType:          int32(temp.ServiceType),
						AvailableReturnBikes: int32(temp.AvailableReturnBikes),
						GeneralBikes:         int32(temp.AvailableRentBikesDetail.GeneralBikes),
						ElectricBikes:        int32(temp.AvailableRentBikesDetail.ElectricBikes),
					}
					pb, err := proto.Marshal(raw)
					if err != nil {
						continue
					}
					pipe.Set(shared.BikeAvailabilityKey(temp.StationUID), pb, 2*time.Minute)
					// Sample into history at most once per 5 minutes per station.
					if db != nil && bikeHistorySampleGate.shouldSample(temp.StationUID, now) {
						historyRows = append(historyRows, []interface{}{
							temp.StationUID, availableRent, int(temp.AvailableReturnBikes), now,
						})
					}
				}
			}
			_ = pipe.Exec()
			log.Infof("[BIKE_ETA] action= %s bike_eta event=complete", city)
		}()
	}
	if db != nil {
		saveBikeAvailabilityHistory(ctx, db, historyRows)
	}
	log.Infof("[BIKE_ETA] action=bike_eta event=complete")
}
