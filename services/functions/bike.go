package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// _bikeAvailabilitySkip lists the cities TDX serves no Bike/Availability feed
// for; bikeEta skips them rather than spending a request per tick on a 404.
var _bikeAvailabilitySkip = map[string]struct{}{
	"Keelung":          {},
	"HsinchuCounty":    {},
	"NantouCounty":     {},
	"YilanCounty":      {},
	"PenghuCounty":     {},
	"KinmenCounty":     {},
	"LienchiangCounty": {},
	"InterCity":        {},
	"HualienCounty":    {},
}

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
	// Bike counts are int32, not uint8: a large station's capacity or live
	// availability exceeds 255 (TDX has returned 321), and a uint8 makes the
	// whole city's payload fail to unmarshal. ServiceStatus/ServiceType stay
	// uint8 — they are small enums, not counts.
	BikesCapacity int32 `json:"BikesCapacity"`
	ServiceType   uint8 `json:"ServiceType"`
}

// bikeAvailability is the subset of a TDX Bike/Availability record used for the
// realtime bike ETA cache (live rentable/returnable counts per station).
type bikeAvailability struct {
	StationUID               string `json:"StationUID"`
	StationID                string `json:"StationID"`
	ServiceStatus            uint8  `json:"ServiceStatus"`
	ServiceType              uint8  `json:"ServiceType"`
	AvailableReturnBikes     int32  `json:"AvailableReturnBikes"`
	AvailableRentBikesDetail struct {
		GeneralBikes  int32 `json:"GeneralBikes"`
		ElectricBikes int32 `json:"ElectricBikes"`
	} `json:"AvailableRentBikesDetail"`
}

// loadBikeStations upserts one city's bike-share stations into bike_stations via
// a temp-table COPY then ON CONFLICT (station_uid) upsert. It consumes an
// already-opened decoder; the "YouBike2.0_" prefix strip, ST_GeomFromText, and
// the temp_bike COPY/upsert are byte-identical to the legacy transform. part is
// the partition value, which for this dataset is the city.
func loadBikeStations(ctx context.Context, dec *json.Decoder, sink loadSink, city string) error {
	if strings.TrimSpace(city) == "" {
		return errors.New("bike stations: city is required")
	}
	stations, err := decodeLoadArray[bikeStation](dec, "bike stations "+city, func(_ int, station bikeStation) error {
		if strings.TrimSpace(station.StationUID) == "" {
			return errors.New("StationUID is required")
		}
		if strings.TrimSpace(station.StationID) == "" {
			return errors.New("StationID is required")
		}
		if !validPosition(station.StationPosition.PositionLon, station.StationPosition.PositionLat) {
			return _oops.With("position_lon", station.StationPosition.PositionLon).With("position_lat", station.StationPosition.PositionLat).Errorf("position is invalid: lon= lat=")
		}
		// ServiceType is stored and served as an opaque smallint, never
		// switched on, so an operator TDX adds later must not reject the
		// city. A value this loader has not seen flows through unchanged.
		return nil
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	seen := make(map[string][]any, len(stations))
	for _, temp := range stations {
		g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
		candidate := []any{
			temp.StationUID,
			temp.StationID,
			strings.TrimPrefix(temp.StationName.ZhTw, "YouBike2.0_"),
			temp.BikesCapacity,
			temp.ServiceType,
			city,
			g,
			temp.StationAddress.ZhTw,
		}
		if err := appendUniqueLoadRow(&row, seen, temp.StationUID, "StationUID", candidate); err != nil {
			return _oops.With("city", city).Wrapf(err, "bike stations")
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
					ON CONFLICT (station_uid) DO UPDATE SET station_id = EXCLUDED.station_id,name = EXCLUDED.name,capacity = EXCLUDED.capacity,service_type = EXCLUDED.service_type,city = excluded.city,geom = EXCLUDED.geom,address = EXCLUDED.address,updated_at = NOW();`,
	}, row)
}

// _bikeHistorySampleGate is the process-wide 5-minute-per-station gate shared
// across bikeEta rounds, so history sampling survives between 30s ticks.
var _bikeHistorySampleGate bikeHistorySampler

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
	zap.S().Infow("start", "component", "bike_eta", "action", "bike_eta", "event", "start")
	now := time.Now()
	var (
		historyRows [][]any
		jobErr      error
	)
	for _, city := range _cities {
		if _, skip := _bikeAvailabilitySkip[city]; skip {
			continue
		}
		if !liveDemandGate(ctx, sink, "bike", city) {
			// Nobody is watching this city and it was fetched within the reduced
			// cadence. The reduced cadence outlives bikeLiveTTL, so re-arm the
			// keys this city owns exactly as its 304 path does (bindFetch) —
			// otherwise an unwatched city's docks would read as "no data" rather
			// than as data a few minutes old.
			ownedKey := shared.LiveOwnedKeysKey("bike", city)
			if err := sink.refreshOwnedTTL(ctx, ownedKey, _bikeLiveTTL); err != nil {
				jobErr = errors.Join(jobErr,
					_oops.With("city", city).Wrapf(err, "refresh unwatched bike TTLs"))
			}
			continue
		}
		zap.S().Infow("city start",
			"component", "bike_eta",
			"action", "bike_eta",
			"city", city,
			"event", "city_start",
		)
		result, err := fetch(ctx, fmt.Sprintf("/v2/Bike/Availability/City/%s", city), "bike_availability"+city)
		if err != nil {
			jobErr = errors.Join(jobErr, _oops.With("city", city).Wrapf(err, "bike fetch"))
			continue
		}
		if !result.Modified {
			// A 304 is the expected answer most ticks: the cadence is well under
			// how often the operators republish. Logged at info because a warning
			// here is 840 lines an hour that never once means anything is wrong.
			zap.S().Warnw("skip",
				"component", "bike_eta",
				"action", "bike_eta",
				"city", city,
				"event", "skip",
				"reason", "not_modified",
			)
			continue
		}
		if err := commitTDXFetch(result, func(dec *json.Decoder) error {
			pipe := sink.pipeline()
			ownedKeys := make([]string, 0)
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
					AvailableReturnBikes: temp.AvailableReturnBikes,
					GeneralBikes:         temp.AvailableRentBikesDetail.GeneralBikes,
					ElectricBikes:        temp.AvailableRentBikesDetail.ElectricBikes,
				}
				pb, err := proto.Marshal(raw)
				if err != nil {
					return err
				}
				key := shared.BikeAvailabilityKey(temp.StationUID)
				pipe.Set(key, pb, _bikeLiveTTL)
				ownedKeys = append(ownedKeys, key)
				// Sample into history at most once per 5 minutes per station.
				if db != nil && _bikeHistorySampleGate.shouldSample(temp.StationUID, now) {
					historyRows = append(historyRows, []any{
						temp.StationUID, availableRent, int(temp.AvailableReturnBikes), now,
					})
				}
				return nil
			}); err != nil {
				return err
			}
			pipe.ReplaceOwnedKeys(shared.LiveOwnedKeysKey("bike", city), ownedKeys, _ownedKeysTTL)
			if err := pipe.Exec(ctx); err != nil {
				return _oops.With("city", city).Wrapf(err, "publish bike availability")
			}
			zap.S().Infow("complete", "component", "bike_eta", "action", "bike_eta", "city", city, "event", "complete")
			return nil
		}); err != nil {
			jobErr = errors.Join(jobErr, _oops.With("city", city).Wrapf(err, "bike process"))
		}
	}
	if db != nil {
		saveBikeAvailabilityHistory(ctx, db, historyRows)
	}
	zap.S().Infow("complete", "component", "bike_eta", "action", "bike_eta", "event", "complete")
	return jobErr
}
