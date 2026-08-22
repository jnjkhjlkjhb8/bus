package gtfs

import (
	"context"
	"strconv"
	"time"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// The GTFS-RT delay producer, TRA half (ADR-0019, FDPL-29).
//
// It is the one delay the feed can state without inferring anything. TDX's
// LiveTrainDelay is TrainNo -> minutes, the static feed's rail trip_id is
// TRA:<TrainNo>:<date>, and the join between them is the identity function. Bus
// delays are the other half and are not this: they need a vehicle matched to a
// departure first, which is where every gate in ADR-0019 lives.
//
// What is emitted is one StopTimeUpdate carrying an arrival delay, placed at the
// station the observation was taken at. GTFS-RT propagates a delay forward from
// the stop it is given, which is exactly the claim TDX is making — this train is
// N minutes late as of here — and no claim at all about the calls it already
// made on time. Placing it on the train's next scheduled stop instead was
// rejected in the ADR: deriving "next stop" from the clock and the timetable is
// a fresh inference that errs worst precisely when a train is most delayed.

// railDelayTrip is one of today's TRA trains: the trip the feed calls it, and
// the stations it calls at.
//
// The stations are held so a delay observed somewhere the train does not stop is
// dropped rather than placed on a stop_id no trip of ours contains. nigiri
// resolves a StopTimeUpdate through the static feed, so an unresolvable stop is
// a silently discarded update at best.
type railDelayTrip struct {
	tripID   string
	stations map[string]bool
}

// _railDelayIndexSQL is today's TRA trains reduced to what a delay needs.
//
// It reads railTripSource and applies the same "more than one call" test
// gtfsTripsSQL's rail branch applies, so the trip_ids here are trip_ids the
// published feed contains. The station list is built from the same stoptimes
// gtfsStopTimesSQL reads, so a station in it has a stop_id in stops.txt.
//
// THSR is excluded by the operator filter rather than by omission: TDX serves no
// delay feed for it, so an index entry could never be used.
var _railDelayIndexSQL = `
SELECT t.train_no,
       t.operator || ':' || t.train_no || ':' || to_char(t.service_date, 'YYYYMMDD') AS trip_id,
       array_agg(DISTINCT c->>'StationID') AS stations
FROM (` + _railTripSource + `) t
CROSS JOIN LATERAL jsonb_array_elements(t.stoptimes) c
WHERE t.operator = 'TRA'
  AND t.service_date = $1::date
  AND jsonb_typeof(t.stoptimes) = 'array'
  AND COALESCE(c->>'StationID', '') <> ''
GROUP BY 1, 2
HAVING count(*) > 1`

// gtfsRTRailDelayStats records why a reported delay did not reach the feed. The
// producer is deliberately silent in several cases, so the silence has to be
// measurable or its coverage is unknowable.
type gtfsRTRailDelayStats struct {
	delaysRead     int
	delaysOnTime   int
	trainNotToday  int
	stationUnknown int
	updates        int
}

// loadRailDelayIndex reads today's TRA trains. It is refreshed on the same daily
// cadence as the bus index: a train number is reused across days, so an index
// built for yesterday would name yesterday's trip.
func loadRailDelayIndex(ctx context.Context, db *pgxpool.Pool, today string) (map[string]railDelayTrip, error) {
	rows, err := db.Query(ctx, _railDelayIndexSQL, today)
	if err != nil {
		return nil, _oops.Wrapf(err, "gtfs-rt: load rail delay index")
	}
	defer rows.Close()
	index := make(map[string]railDelayTrip, 2048)
	for rows.Next() {
		var trainNo, tripID string
		var stations []string
		if err := rows.Scan(&trainNo, &tripID, &stations); err != nil {
			return nil, _oops.Wrapf(err, "gtfs-rt: load rail delay index: scan")
		}
		set := make(map[string]bool, len(stations))
		for _, station := range stations {
			set[station] = true
		}
		index[trainNo] = railDelayTrip{tripID: tripID, stations: set}
	}
	if err := rows.Err(); err != nil {
		return nil, _oops.Wrapf(err, "gtfs-rt: load rail delay index: rows")
	}
	return index, nil
}

// readRailDelays reads the two hashes rail.TraEta writes: the delay in minutes and
// the station it was measured at. A train present in one and not the other is
// left to buildGTFSRTRailDelays to drop.
func readRailDelays(ctx context.Context, rc *redis.Client) (map[string]string, map[string]string, error) {
	minutes, err := rc.HGetAll(ctx, shared.TraDelayHashKey).Result()
	if err != nil {
		return nil, nil, _oops.Wrapf(err, "gtfs-rt: read TRA delays")
	}
	stations, err := rc.HGetAll(ctx, shared.TraDelayStationKey).Result()
	if err != nil {
		return nil, nil, _oops.Wrapf(err, "gtfs-rt: read TRA delay stations")
	}
	return minutes, stations, nil
}

// buildGTFSRTRailDelays turns the reported delays into TripUpdates.
//
// Four things are dropped, each counted: a train reported on time (there is
// nothing to say, and saying "delay 0" would overwrite a consumer's own better
// estimate), a value that does not parse, a train not running today, and an
// observation taken at a station the train does not call at.
func buildGTFSRTRailDelays(
	index map[string]railDelayTrip,
	minutes, stations map[string]string,
	now time.Time,
) ([]*gtfs.FeedEntity, gtfsRTRailDelayStats) {
	stats := gtfsRTRailDelayStats{delaysRead: len(minutes)}
	date := now.Format("20060102")
	entities := make([]*gtfs.FeedEntity, 0, len(minutes))
	for trainNo, raw := range minutes {
		late, err := strconv.Atoi(raw)
		if err != nil {
			continue
		}
		if late <= 0 {
			stats.delaysOnTime++
			continue
		}
		trip, running := index[trainNo]
		if !running {
			stats.trainNotToday++
			continue
		}
		station := stations[trainNo]
		if station == "" || !trip.stations[station] {
			stats.stationUnknown++
			continue
		}
		stats.updates++
		entities = append(entities, &gtfs.FeedEntity{
			Id: proto.String(trip.tripID),
			TripUpdate: &gtfs.TripUpdate{
				Trip: &gtfs.TripDescriptor{
					TripId:               proto.String(trip.tripID),
					StartDate:            proto.String(date),
					ScheduleRelationship: gtfs.TripDescriptor_SCHEDULED.Enum(),
				},
				StopTimeUpdate: []*gtfs.TripUpdate_StopTimeUpdate{{
					StopId: proto.String(railDelayStopID(station)),
					// Arrival only: GTFS-RT reads a missing departure as carrying
					// the same delay, and a train held at a platform is the one
					// case where stating both would be inventing the difference.
					Arrival: &gtfs.TripUpdate_StopTimeEvent{
						// tra:delay is minutes; GTFS-RT delay is seconds.
						// docs/redis.md called them seconds and was wrong — the
						// app has always read them as minutes — so this factor
						// is the load-bearing line of the whole producer.
						Delay: proto.Int32(int32(late) * 60),
					},
				}},
			},
		})
	}
	return entities, stats
}

// railDelayStopID is the platform stop_times references, which is what a
// StopTimeUpdate has to name: the station node itself is a parent station and no
// trip calls at it.
func railDelayStopID(stationID string) string {
	return "TRA:" + stationID + ":platform"
}

// logGTFSRTRailDelayStats reports the producer's coverage. Every drop is a delay TDX
// published that the feed does not carry, so the counters are the only way to
// tell a quiet day from a broken join.
func logGTFSRTRailDelayStats(stats gtfsRTRailDelayStats) {
	zap.S().Infow("built",
		"component", "gtfs_rt",
		"action", "delay",
		"event", "built",
		"delays_read", stats.delaysRead,
		"delays_on_time", stats.delaysOnTime,
		"train_not_today", stats.trainNotToday,
		"station_unknown", stats.stationUnknown,
		"updates", stats.updates,
	)
}
