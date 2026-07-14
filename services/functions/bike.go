package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

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

// loadBikeStations upserts one city's bike-share stations into bike_stations via
// a temp-table COPY then ON CONFLICT (station_uid) upsert. It consumes an
// already-opened decoder; the "YouBike2.0_" prefix strip, ST_GeomFromText, and
// the temp_bike COPY/upsert are byte-identical to the legacy transform. part is
// the partition value, which for this dataset is the city.
func loadBikeStations(ctx context.Context, dec *json.Decoder, sink loadSink, city string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[BIKE] action=getbike_station city=%s event=decode_error error=%v", city, err.Error())
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp bikeStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []any{
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
	if len(row) == 0 {
		return nil
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "bike",
		createSQL: `CREATE TEMP TABLE temp_bike (
                            uid text,
                            id text,
                            name text,
                            cap int,
                            type int,
							city text,
                            geom text,
                            addr text
					) ON COMMIT DROP`,
		tempTable: "temp_bike",
		copyCols:  []string{"uid", "id", "name", "cap", "type", "city", "geom", "addr"},
		insertSQL: `INSERT INTO bike_stations (
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
					ON CONFLICT (station_uid) DO UPDATE SET name = EXCLUDED.name,capacity = EXCLUDED.capacity,service_type = EXCLUDED.service_type,city = excluded.city,geom = EXCLUDED.geom,address = EXCLUDED.address,updated_at = NOW();`,
	}, row)
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
func bikeEta(ctx context.Context, fetch boundFetch, sink liveSink, db *pgxpool.Pool) error {
	log.Infof("[BIKE_ETA] action=bike_eta event=start")
	now := time.Now()
	var historyRows [][]interface{}
	var jobErr error
	for _, city := range cities {
		if city == "Keelung" || city == "HsinchuCounty" || city == "NantouCounty" || city == "YilanCounty" || city == "PenghuCounty" || city == "KinmenCounty" || city == "LienchiangCounty" || city == "InterCity" || city == "HualienCounty" {
			continue
		}
		log.Infof("[BIKE_ETA] action=bike_eta city=%s event=city_start", city)
		result, err := fetch(ctx, fmt.Sprintf("/v2/Bike/Availability/City/%s", city), "bike_availability"+city)
		if err != nil {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=skip reason=api_error,error=%s", city, err)
			jobErr = errors.Join(jobErr, fmt.Errorf("bike %s fetch: %w", city, err))
			continue
		}
		if !result.Modified {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=skip reason=no updated", city)
			continue
		}
		if err := commitTDXFetch(result, func(dec *json.Decoder) error {
			pipe := sink.pipeline()
			// Availability Set and the interleaved history sampling keep bikeEta on
			// the streaming strict decoder rather than the per-item-proto
			// publisher: the history append is a per-item side effect the publisher
			// does not model.
			if err := decodeLiveItems(dec, func(temp bikeAvailability) error {
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
					return err
				}
				pipe.Set(shared.BikeAvailabilityKey(temp.StationUID), pb, bikeLiveTTL)
				// Sample into history at most once per 5 minutes per station.
				if db != nil && bikeHistorySampleGate.shouldSample(temp.StationUID, now) {
					historyRows = append(historyRows, []any{
						temp.StationUID, availableRent, int(temp.AvailableReturnBikes), now,
					})
				}
				return nil
			}); err != nil {
				return err
			}
			if err := pipe.Exec(); err != nil {
				return err
			}
			log.Infof("[BIKE_ETA] action= %s bike_eta event=complete", city)
			return nil
		}); err != nil {
			log.Infof("[BIKE_ETA] action=bike_eta city=%s event=process_error error=%v", city, err)
			jobErr = errors.Join(jobErr, fmt.Errorf("bike %s process: %w", city, err))
		}
	}
	if db != nil {
		saveBikeAvailabilityHistory(ctx, db, historyRows)
	}
	log.Infof("[BIKE_ETA] action=bike_eta event=complete")
	return jobErr
}
