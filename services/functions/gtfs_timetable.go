package main

import (
	"strconv"
	"time"
)

// GTFS timetable files: trips, stop_times, calendar_dates, frequencies,
// transfers and shapes. Split out of gtfs_files.go for size; that file
// documents the identifier scheme every statement assumes.

// ---------------------------------------------------------------------------
// Timetable files: trips, calls, service days and metro headways.
// ---------------------------------------------------------------------------

// gtfsMidnightGap is the longest wait between two consecutive calls that a
// midnight rollover may imply. Beyond it a time that moves backwards is read as
// bad data rather than as a new day (gtfsStopTimesSQL).
const gtfsMidnightGap = 3 * time.Hour

// gtfsMidnightGapSecs is gtfsMidnightGap in the units the calls are compared in,
// which is what the statement can splice.
var gtfsMidnightGapSecs = strconv.Itoa(int(gtfsMidnightGap / time.Second))

// gtfsCalendarDays is how many days of service the feed states, counting from
// the day it is built.
//
// Rail is the only mode landed as a per-date expansion, so before this bound
// existed the window was simply however far TDX had landed — ~85 days, which is
// 91,875 of the feed's 209,894 trips and a third of its calls. Nothing needs
// that reach: the app answers a rail timetable query straight out of PostgreSQL
// (ADR-0005), and this feed exists to plan journeys, which nobody does three
// months out. The feed is rebuilt nightly, so the window always carries a
// fortnight of slack against a run that fails.
const gtfsCalendarDays = 15

// railTripRows flattens both daily-timetable tables to one shape.
//
// The two differ in ways that have to be reconciled before anything else can be
// shared: tra_dailytimetable.traindate is text while thsr_dailytimetable's is
// timestamptz landed at Taipei midnight (so it must be read back in Taipei, not
// in the services' UTC session), and only TRA carries train types, suspension
// flags and wheelchair flags.
//
// Read railTripSource, not this: every consumer wants the windowed set.
const railTripRows = `
  SELECT
    'TRA' AS operator,
    dailytraininfo->>'TrainNo' AS train_no,
    traindate::date AS service_date,
    'TRA:' || (dailytraininfo->>'TrainTypeID') AS route_id,
    dailytraininfo->'EndingStationName'->>'Zh_tw' AS headsign,
    COALESCE((dailytraininfo->>'Direction')::int, 0) AS direction_id,
    CASE WHEN (dailytraininfo->>'WheelchairFlag')::int = 1 THEN 1 ELSE 0 END AS wheelchair,
    stoptimes
  FROM raw_tdx.tra_dailytimetable
  WHERE COALESCE(dailytraininfo->>'TrainNo', '') <> ''
    AND COALESCE(dailytraininfo->>'TrainTypeID', '') <> ''
    -- A cancelled train must not be planned onto. TDX keeps the row and flags it.
    AND COALESCE((dailytraininfo->>'SuspendedFlag')::int, 0) = 0
  UNION ALL
  SELECT
    'THSR',
    dailytraininfo->>'TrainNo',
    (traindate AT TIME ZONE 'Asia/Taipei')::date,
    'THSR',
    dailytraininfo->'EndingStationName'->>'Zh_tw',
    COALESCE((dailytraininfo->>'Direction')::int, 0),
    0,
    stoptimes
  FROM raw_tdx.thsr_dailytimetable
  WHERE COALESCE(dailytraininfo->>'TrainNo', '') <> ''`

// railTripSource is railTripRows cut to the feed's window.
//
// The bound lives here rather than on calendar_dates because trips.txt and
// stop_times.txt read this set too and derive their service_id from the date in
// it. Trimming only the calendar would leave every trip past the window naming
// a service no date ever states, which is not a shorter feed but a broken one.
//
// now() is stable for the length of a transaction, and the whole archive is
// written inside one (writeGTFSArchive), so every file resolves the window to
// the same fortnight however long the build runs.
var railTripSource = `
  SELECT * FROM (` + railTripRows + `) w
  WHERE w.service_date >= (now() AT TIME ZONE 'Asia/Taipei')::date
    AND w.service_date < (now() AT TIME ZONE 'Asia/Taipei')::date + ` +
	strconv.Itoa(gtfsCalendarDays)

// gtfsCalendarDatesSQL emits one service per date the timetable covers.
//
// calendar.txt is not used: rail is landed as a per-date expansion, so its
// services are single dates and there is no weekly pattern to state. Expanding
// rather than inferring is also what makes public holidays and added or
// cancelled workings correct for free — they are already baked into the dates
// TDX served.
//
// The range every weekly mask is expanded over is the dates rail states, which
// railTripSource has already cut to gtfsCalendarDays. Rail is what sets it
// because it is the only mode landed per date — the bus daily timetable lands
// one day and is published here as a weekday mask.
var gtfsCalendarDatesSQL = `
WITH day AS (
  -- The feed's calendar range: every date any timetable covers. Only rail
  -- carries dates — every bus trip now runs on a weekday mask — so rail alone
  -- sets how far ahead the masks below are expanded.
  --
  -- DISTINCT is load-bearing, not tidiness: railTripSource is one row per train
  -- per date, so without it the mask branch below cross joins every service
  -- against every train running that day and states the same (service, date) a
  -- few thousand times over. It made calendar_dates.txt 3,178,308 rows where
  -- 3,204 say the same thing, and every one of the repeats is a duplicate
  -- primary key a validator rejects.
  SELECT DISTINCT service_date FROM (` + railTripSource + `) r
), svc AS (
  SELECT * FROM (` + metroServiceSQL + `) m
  UNION
  SELECT * FROM (` + busScheduleServiceSQL + `) b
)
-- Rail runs to a date TDX already resolved.
SELECT DISTINCT
  'D' || to_char(service_date, 'YYYYMMDD') AS service_id,
  to_char(service_date, 'YYYYMMDD') AS date,
  1 AS exception_type
FROM day
UNION ALL
-- Metro headways and weekly bus schedules are weekday masks, expanded onto the
-- same range so the feed has one calendar mechanism instead of a calendar.txt
-- alongside this file. Both modes share the service ids: a mask is a mask.
-- EXTRACT(DOW) is 0 for Sunday, which is why svc.week is ordered from Sunday.
SELECT svc.service_id, to_char(day.service_date, 'YYYYMMDD'), 1
FROM day CROSS JOIN svc
WHERE svc.week[EXTRACT(DOW FROM day.service_date)::int + 1]
ORDER BY 1, 2`

// gtfsTripsSQL emits one trip per train per service date.
//
// trip_id embeds the train number and the date rather than being a surrogate:
// it has to stay stable across nightly rebuilds so a GTFS-RT TripUpdate can name
// it, and TrainNo is the identifier the realtime delay feed reports against.
var gtfsTripsSQL = `
-- DISTINCT ON collapses the handful of subroutes that run two departures in the
-- same minute, which would otherwise share a trip_id. Merging them loses one
-- departure; emitting both would make the file invalid and interleave their
-- calls into a journey that does not exist.
SELECT DISTINCT ON (trip_id)
       route_id, service_id, trip_id, trip_headsign, trip_short_name,
       -- TDX's third direction is 迴圈 (circular), which GTFS has no value for:
       -- direction_id is a two-way label, not a route shape. A circular route is
       -- reported as the outbound one, which is what a rider boarding it is
       -- doing. Clamped here rather than at the source because trip_id and
       -- shape_id are built from the raw value and must keep matching
       -- bus_shape.direction.
       LEAST(direction_id, 1) AS direction_id,
       wheelchair_accessible, shape_id
FROM (
  SELECT
    route_id,
    'D' || to_char(service_date, 'YYYYMMDD') AS service_id,
    operator || ':' || train_no || ':' || to_char(service_date, 'YYYYMMDD') AS trip_id,
    COALESCE(headsign, '') AS trip_headsign,
    train_no AS trip_short_name,
    direction_id,
    wheelchair AS wheelchair_accessible,
    -- No shape: rail_shapes is per line and a train crosses lines.
    '' AS shape_id
  FROM (` + railTripSource + `) t
  WHERE jsonb_typeof(stoptimes) = 'array' AND jsonb_array_length(stoptimes) > 1
  UNION ALL
  SELECT
    routeuid,
    service_id,
    trip_id,
    COALESCE(headsign, ''),
    '',
    direction_id,
    wheelchair,
    CASE WHEN EXISTS (
      SELECT 1 FROM raw_tdx.bus_shape sh
      WHERE sh.subrouteuid = split_part(trip_id, ':', 1)
        AND COALESCE(sh.direction, 0) = direction_id
        AND sh.geometry LIKE 'LINESTRING%'
    ) THEN 'B:' || split_part(trip_id, ':', 1) || ':' || direction_id::text
    ELSE '' END
  FROM (` + busScheduleSource + `) w
  UNION ALL
  -- One template trip per metro route direction. A frequency-based trip states
  -- the shape of the journey once; frequencies.txt says how often it repeats.
  -- Running every departure as its own trip would need StationTimeTable joined
  -- across stations, which is exactly the join that does not hold.
  SELECT DISTINCT
    p.system || ':' || p.routeid,
    svc.service_id,
    'M:' || p.system || ':' || p.routeid || ':' || p.direction::text || ':' || svc.service_id,
    '',
    '',
    p.direction,
    0,
    COALESCE((SELECT 'M:' || m.system || ':' || m.lineid
              FROM raw_tdx.metro_route r
              JOIN raw_tdx.metro_shape m ON m.system = r.system AND m.lineid = r.lineid
              WHERE r.system = p.system AND r.routeid = p.routeid
                AND m.geometry LIKE 'LINESTRING%' LIMIT 1), '')
  FROM (` + metroPatternSQL + `) p
  JOIN raw_tdx.metro_frequency f ON f.system = p.system AND f.routeid = p.routeid
  JOIN (` + metroServiceSQL + `) svc
    ON svc.service_id = ` + gtfsWeekMaskSQL("f.serviceday") + `
  WHERE p.complete
  UNION ALL
  -- Most cities publish an origin departure and nothing else, so the schedule
  -- source above filters every one of their trips out. These are laid out from
  -- bus_segment_time instead (gtfs_bus_pattern.go).
  SELECT * FROM (` + busPatternTripsSQL + `) bp
) t
WHERE trip_id <> ''
  -- A trip is only published if its calls are: gtfsStopTimesSQL drops the ones
  -- whose times it cannot state, and a trip row with no stop_times is one a
  -- planner can board and never leave. Reading the materialized calls rather
  -- than deriving them again is what makes this affordable.
  AND trip_id IN (SELECT trip_id FROM ` + gtfsStopTimeTable + `)
ORDER BY trip_id`

// gtfsStopTimesSQL emits each trip's calls.
//
// Times cross midnight and GTFS requires them to increase within a trip, so a
// train that departs 23:50 and arrives 00:20 must be written 24:20:00, not
// 00:20:00. TDX wraps instead, and nothing in the payload says it wrapped, so
// the rollover is recovered by watching for a time that moves backwards along
// the stop sequence and adding a day from there on. Getting this wrong does not
// fail anything loudly — it silently produces last trains that cannot be
// boarded.
//
// A stop flagged suspended stays in the sequence with pickup and drop-off
// disabled rather than being removed: the train still passes through, and
// deleting the row would make the surrounding times look like a direct run.
var gtfsStopTimesSQL = `
WITH calls AS (
  -- Rail and bus share a shape: a per-call list with wall-clock HH:MM.
  SELECT
    t.operator || ':' || t.train_no || ':' || to_char(t.service_date, 'YYYYMMDD') AS trip_id,
    (c->>'StopSequence')::int AS stop_sequence,
    t.operator || ':' || (c->>'StationID') || ':platform' AS stop_id,
    split_part(c->>'ArrivalTime', ':', 1)::int * 3600
      + split_part(c->>'ArrivalTime', ':', 2)::int * 60 AS arr,
    split_part(c->>'DepartureTime', ':', 1)::int * 3600
      + split_part(c->>'DepartureTime', ':', 2)::int * 60 AS dep,
    COALESCE((c->>'SuspendedFlag')::int, 0) AS suspended
  FROM (` + railTripSource + `) t
  CROSS JOIN LATERAL jsonb_array_elements(t.stoptimes) c
  WHERE jsonb_typeof(t.stoptimes) = 'array'
    AND (c->>'ArrivalTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
    AND (c->>'DepartureTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
  UNION ALL
  SELECT
    w.trip_id,
    (c->>'StopSequence')::int,
    c->>'StopUID',
    split_part(c->>'ArrivalTime', ':', 1)::int * 3600
      + split_part(c->>'ArrivalTime', ':', 2)::int * 60,
    split_part(c->>'DepartureTime', ':', 1)::int * 3600
      + split_part(c->>'DepartureTime', ':', 2)::int * 60,
    0
  FROM (` + busScheduleSource + `) w
  CROSS JOIN LATERAL jsonb_array_elements(w.stop_times) c
  WHERE (c->>'ArrivalTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
    AND (c->>'DepartureTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
    AND COALESCE(c->>'StopUID', '') <> ''
  UNION ALL
  -- The origin-only networks: departure plus each stop's accumulated running
  -- time, rather than a call list the source never published.
  SELECT trip_id, stop_sequence, stop_id, arr, dep, suspended
  FROM (` + busPatternStopTimesSQL + `) bps
), deduped AS (
  -- stop_sequence is renumbered rather than copied. TDX repeats StopSequence
  -- within a trip on some subroutes — 445 bus trips collapsed to a single call
  -- when the source value was taken as a key — and GTFS only requires the
  -- sequence to increase, not to match upstream. Ordering by the source value
  -- first keeps TDX's intended call order.
  --
  -- The DISTINCT ON also collapses the few subroutes that run two departures in
  -- the same minute and therefore share a trip_id: one trip is better than two
  -- interleaved into a journey that does not exist.
  SELECT DISTINCT ON (trip_id, stop_id)
    trip_id, stop_id, arr, dep, suspended,
    ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY stop_sequence, arr, stop_id)::int AS stop_sequence
  FROM calls
  ORDER BY trip_id, stop_id, stop_sequence
), lagged AS (
  -- LAG and SUM must live in separate levels: PostgreSQL rejects a window
  -- function nested inside another window function's argument.
  SELECT *, LAG(arr) OVER (PARTITION BY trip_id ORDER BY stop_sequence) AS prev_arr
  FROM deduped
), rolled AS (
  -- A time that moves backwards is either midnight or bad data, and the two are
  -- told apart by what the rollover would imply about the wait between the two
  -- stops. 23:50 -> 00:20 implies half an hour, which is a bus. 07:42 -> 07:13
  -- implies 23 and a half hours, which is nothing.
  --
  -- Measured over the 2026-08-06 feed: 2,763 trips roll over with every implied
  -- gap under three hours and all of them start at 23:xx, while 1,613 imply gaps
  -- of 12 to 23 hours. Nothing at all falls between 3 and 12, so the threshold
  -- sits in an empty band rather than through a distribution.
  SELECT *,
    SUM(CASE WHEN prev_arr IS NOT NULL AND arr < prev_arr
                  AND arr + 86400 - prev_arr <= ` + gtfsMidnightGapSecs + ` THEN 1 ELSE 0 END)
      OVER (PARTITION BY trip_id ORDER BY stop_sequence
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS day_offset,
    -- One unexplainable step condemns the whole trip. The calls after it are a
    -- consistent run at the wrong time of day, so there is no prefix worth
    -- keeping: published either way round, this trip tells a planner a bus
    -- arrives a day late.
    MAX(CASE WHEN prev_arr IS NOT NULL AND arr < prev_arr
                  AND arr + 86400 - prev_arr > ` + gtfsMidnightGapSecs + ` THEN 1 ELSE 0 END)
      OVER (PARTITION BY trip_id) AS broken
  FROM lagged
), timed AS (
  SELECT trip_id, stop_id, stop_sequence, suspended,
    day_offset * 86400 + arr AS arr_s,
    day_offset * 86400 + CASE WHEN dep < arr THEN dep + 86400 ELSE dep END AS dep_s
  FROM rolled
  WHERE broken = 0
  UNION ALL
  -- Metro template trips carry offsets from the journey's start, not wall-clock
  -- times: frequencies.txt anchors them. Starting at zero is the plain reading
  -- of "this journey takes this long".
  SELECT
    'M:' || p.system || ':' || p.routeid || ':' || p.direction::text || ':' || svc.service_id,
    p.system || ':' || p.station_id || ':platform',
    p.stop_sequence,
    0,
    p.offset_secs,
    p.offset_secs
  FROM (` + metroPatternSQL + `) p
  JOIN raw_tdx.metro_frequency f ON f.system = p.system AND f.routeid = p.routeid
  JOIN (` + metroServiceSQL + `) svc
    ON svc.service_id = ` + gtfsWeekMaskSQL("f.serviceday") + `
  WHERE p.complete
)
SELECT DISTINCT
  trip_id,
  -- Formatted by hand rather than through to_char: GTFS needs hours past 24 to
  -- keep counting up (a 00:20 arrival on a train that left at 23:50 is 24:20:00),
  -- and every interval formatter wraps them back to 00.
  lpad((arr_s / 3600)::text, 2, '0') || ':' ||
    lpad(((arr_s % 3600) / 60)::text, 2, '0') || ':' ||
    lpad((arr_s % 60)::text, 2, '0') AS arrival_time,
  lpad((dep_s / 3600)::text, 2, '0') || ':' ||
    lpad(((dep_s % 3600) / 60)::text, 2, '0') || ':' ||
    lpad((dep_s % 60)::text, 2, '0') AS departure_time,
  stop_id,
  stop_sequence,
  suspended AS pickup_type,
  suspended AS drop_off_type
FROM timed
ORDER BY trip_id, stop_sequence`

// gtfsFrequenciesSQL states how often each metro template trip repeats.
//
// exact_times is 0: the headway is a band ("a train every 4 to 6 minutes"), not
// a schedule, so a planner should treat departures as evenly spread rather than
// timetabled. MinHeadwayMins is used because a rider's wait is bounded by the
// shortest interval on offer, and the difference between the two is a minute or
// two on the systems this covers.
//
// A headway row carries no direction while a trip does, so each band applies to
// both directions of its route.
var gtfsFrequenciesSQL = `
SELECT DISTINCT ON (trip_id, start_time, end_time)
  trip_id, start_time, end_time, headway_secs, exact_times
FROM (
SELECT
  'M:' || p.system || ':' || p.routeid || ':' || p.direction::text || ':' || svc.service_id AS trip_id,
  h->>'StartTime' || ':00' AS start_time,
  CASE WHEN h->>'EndTime' = '00:00' THEN '24:00:00' ELSE h->>'EndTime' || ':00' END AS end_time,
  ((h->>'MinHeadwayMins')::int * 60) AS headway_secs,
  0 AS exact_times
FROM raw_tdx.metro_frequency f
CROSS JOIN LATERAL jsonb_array_elements(f.headways) h
JOIN (SELECT DISTINCT system, routeid, direction FROM (` + metroPatternSQL + `) q WHERE q.complete) p
  ON p.system = f.system AND p.routeid = f.routeid
JOIN (` + metroServiceSQL + `) svc
  ON svc.service_id = ` + gtfsWeekMaskSQL("f.serviceday") + `
WHERE jsonb_typeof(f.headways) = 'array'
  AND (h->>'StartTime') ~ '^[0-9]{2}:[0-9]{2}$'
  AND (h->>'EndTime') ~ '^[0-9]{2}:[0-9]{2}$'
  AND (h->>'MinHeadwayMins') ~ '^[0-9]+$'
  AND (h->>'MinHeadwayMins')::int > 0
  AND h->>'StartTime' < h->>'EndTime'
) b
-- TDX serves some windows twice for one route, differing only in headway
-- (Kaohsiung's orange line lists 18:30-23:00 at both 6 and 4 minutes), and GTFS
-- forbids two bands covering the same time. The shorter headway wins for the
-- same reason MinHeadwayMins is used at all: a rider's wait is bounded by the
-- best service on offer.
ORDER BY trip_id, start_time, end_time, headway_secs`

// metroPatternSQL is the ordered station list of every metro route direction,
// with each station's cumulative seconds from the route's origin.
//
// Metro stop_times are derived rather than read. StationTimeTable has no train
// identifier — its Sequence is the Nth departure at that station, and it does
// not line up across stations once a route has any short working, which is
// demonstrable on the Bannan line — so joining stations on it invents trips that
// do not run. What is reliable is the running time between adjacent stations,
// which S2STravelTime states directly, so the shape of a journey is built from
// the segment times and the departure list only anchors it.
//
// StopTime is added to RunTime because a rider's clock includes the dwell.
const metroPatternSQL = `
  WITH system_size AS (
    -- The longest route each system runs, in hops. Used to reject segment rows
    -- that cannot describe that system's network.
    SELECT system, MAX(jsonb_array_length(stations)) - 1 AS max_hops
    FROM raw_tdx.metro_stationofroute
    WHERE jsonb_typeof(stations) = 'array'
    GROUP BY 1
  ), seg AS (
    -- Structural guard, not just a NULL check. Kaohsiung's light rail lands 742
    -- segments for a 38-station loop and Taoyuan lands 462 for a 22-station line
    -- with an empty routeid; both summed to hundreds of hours. Because the
    -- lookup matches on (system, from, to) alone, every hop still resolved and a
    -- nullness-based completeness test passed them.
    --
    -- Three times the longest route's hop count leaves room for a system whose
    -- rows legitimately cover both directions and several service patterns,
    -- while rejecting a row that is an order of magnitude too large. The bound
    -- is deliberately not derived from Route.TravelTime: that field is itself
    -- wrong on Taichung, where it claims 71 minutes for a 35-minute line.
    SELECT s.system,
           tt->>'FromStationID' AS from_id,
           tt->>'ToStationID' AS to_id,
           MAX((tt->>'RunTime')::int + COALESCE((tt->>'StopTime')::int, 0)) AS secs
    FROM raw_tdx.metro_s2straveltime s
    JOIN system_size z ON z.system = s.system
    CROSS JOIN LATERAL jsonb_array_elements(s.traveltimes) tt
    WHERE jsonb_typeof(s.traveltimes) = 'array'
      AND jsonb_array_length(s.traveltimes) <= GREATEST(z.max_hops, 1) * 3
      AND COALESCE(tt->>'FromStationID', '') <> ''
      AND COALESCE(tt->>'ToStationID', '') <> ''
      AND (tt->>'RunTime') ~ '^[0-9]+$'
    GROUP BY 1, 2, 3
  ), station AS (
    SELECT r.system, r.routeid, r.direction,
           st.ordinality::int AS stop_sequence,
           st.value->>'StationID' AS station_id
    FROM raw_tdx.metro_stationofroute r
    CROSS JOIN LATERAL jsonb_array_elements(r.stations) WITH ORDINALITY st(value, ordinality)
    WHERE jsonb_typeof(r.stations) = 'array'
      AND COALESCE(st.value->>'StationID', '') <> ''
  ), linked AS (
    SELECT s.*,
           LAG(s.station_id) OVER (PARTITION BY s.system, s.routeid, s.direction
                                   ORDER BY s.stop_sequence) AS prev_station
    FROM station s
  )
  SELECT l.system, l.routeid, l.direction, l.stop_sequence, l.station_id,
         SUM(COALESCE(g.secs, 0)) OVER (PARTITION BY l.system, l.routeid, l.direction
                                        ORDER BY l.stop_sequence
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS offset_secs,
         -- A route direction is only usable when every one of its hops has a
         -- known running time; one missing segment would silently compress the
         -- whole downstream journey.
         BOOL_AND(l.prev_station IS NULL OR g.secs IS NOT NULL)
           OVER (PARTITION BY l.system, l.routeid, l.direction) AS complete
  FROM linked l
  LEFT JOIN seg g ON g.system = l.system
                 AND g.from_id = l.prev_station
                 AND g.to_id = l.station_id`

// gtfsWeekMaskSQL and gtfsWeekArraySQL turn a TDX ServiceDay object into a
// service identity shared by every mode that runs to a weekly pattern.
//
// The mask is spelled out rather than hashed so a service id says what it means:
// W:1111100 is Monday to Friday. Anything with the same mask is the same
// service, which keeps the count at a handful rather than one per route, and
// lets metro headways and bus schedules share one set of services instead of
// each inventing its own.
//
// The array is ordered from Sunday because EXTRACT(DOW) is 0 for Sunday.
func gtfsWeekMaskSQL(col string) string {
	return `'W:' || (` + col + `->>'Monday')::boolean::int::text
	     || (` + col + `->>'Tuesday')::boolean::int::text
	     || (` + col + `->>'Wednesday')::boolean::int::text
	     || (` + col + `->>'Thursday')::boolean::int::text
	     || (` + col + `->>'Friday')::boolean::int::text
	     || (` + col + `->>'Saturday')::boolean::int::text
	     || (` + col + `->>'Sunday')::boolean::int::text`
}

func gtfsWeekArraySQL(col string) string {
	return `ARRAY[
		(` + col + `->>'Sunday')::boolean, (` + col + `->>'Monday')::boolean,
		(` + col + `->>'Tuesday')::boolean, (` + col + `->>'Wednesday')::boolean,
		(` + col + `->>'Thursday')::boolean, (` + col + `->>'Friday')::boolean,
		(` + col + `->>'Saturday')::boolean]`
}

// busScheduleSource is the weekly bus timetable, and with busOriginTripSource
// the only thing the static feed is built from.
//
// bus_dailytimetable is deliberately not a source here. It is a single-day
// expansion — TDX serves today only and the landing keeps one date — so a trip
// taken from it can state no recurrence, and on the 2026-07-31 build 24,875 bus
// trips were pinned to that one date while the rail half of the same feed ran
// 85. bus_schedule states a ServiceDay mask per departure, which is what a
// planner asked about next Tuesday needs. The cost is measured and paid: 73 of
// the 2,976 route directions the daily timetable carries have no schedule
// row or no usable pattern and leave the feed with this change.
//
// It is filtered to trips that carry real per-stop times. Measured across the
// landed data, only Kaohsiung does (averaging 31.9 calls per trip); Taipei, New
// Taipei, Tainan and Taichung all average 1.0, meaning a departure time at the
// origin and nothing else. Those go through busOriginTripSource instead, which
// takes exactly the entries this one rejects, so the two never emit the same
// departure twice.
var busScheduleSource = `
  SELECT
    s.routeuid,
    s.subrouteuid || ':' || COALESCE(s.direction, 0)::text || ':'
      || replace(t.value->'StopTimes'->0->>'DepartureTime', ':', '') || ':'
      || ` + gtfsWeekMaskSQL("t.value->'ServiceDay'") + ` AS trip_id,
    ` + gtfsWeekMaskSQL("t.value->'ServiceDay'") + ` AS service_id,
    COALESCE(s.direction, 0) AS direction_id,
    s.subroutename->>'Zh_tw' AS headsign,
    CASE WHEN (t.value->>'IsLowFloor')::boolean THEN 1 ELSE 0 END AS wheelchair,
    t.value->'StopTimes' AS stop_times
  FROM raw_tdx.bus_schedule s
  CROSS JOIN LATERAL jsonb_array_elements(s.timetables) t
  WHERE jsonb_typeof(s.timetables) = 'array'
    AND jsonb_typeof(t.value->'StopTimes') = 'array'
    AND jsonb_typeof(t.value->'ServiceDay') = 'object'
    AND COALESCE(s.subrouteuid, '') <> ''
    AND COALESCE(s.routeuid, '') <> ''
    AND (t.value->'StopTimes'->0->>'DepartureTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
    AND (
      SELECT count(DISTINCT c->>'StopUID') FROM jsonb_array_elements(t.value->'StopTimes') c
      WHERE (c->>'ArrivalTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
        AND (c->>'DepartureTime') ~ '^[0-9]{1,2}:[0-9]{2}$'
        AND COALESCE(c->>'StopUID', '') <> ''
    ) > 1
    AND (
      SELECT count(*) = count(DISTINCT c->>'StopSequence')
      FROM jsonb_array_elements(t.value->'StopTimes') c
    )`

// busScheduleServiceSQL is the weekday-mask service set the bus schedule needs,
// in the same shape metroServiceSQL produces so calendar_dates expands both the
// same way.
var busScheduleServiceSQL = `
  SELECT DISTINCT
    ` + gtfsWeekMaskSQL("t.value->'ServiceDay'") + ` AS service_id,
    ` + gtfsWeekArraySQL("t.value->'ServiceDay'") + ` AS week
  FROM raw_tdx.bus_schedule s
  CROSS JOIN LATERAL jsonb_array_elements(s.timetables) t
  WHERE jsonb_typeof(s.timetables) = 'array'
    AND jsonb_typeof(t.value->'ServiceDay') = 'object'`

// metroServiceSQL turns each headway row's weekday mask into a service id.
//
// The mask is spelled out rather than hashed so a service id says what it means:
// M:1111100 is Monday to Friday. Two routes with the same mask share a service,
// which is what keeps the count at a handful rather than one per route.
var metroServiceSQL = `
  SELECT DISTINCT
    ` + gtfsWeekMaskSQL("serviceday") + ` AS service_id,
    ` + gtfsWeekArraySQL("serviceday") + ` AS week
  FROM raw_tdx.metro_frequency
  WHERE jsonb_typeof(serviceday) = 'object'
    AND system IN (SELECT DISTINCT system FROM raw_tdx.metro_s2straveltime)`

// gtfsTransfersSQL states the interchanges a planner cannot work out for itself.
//
// Only metro line-to-line transfers are emitted. TDX measured these — the walk
// from one platform to another inside a station — and no amount of street data
// recovers them, because the walk never leaves the building. Taipei Main's
// Bannan-to-Tamsui interchange is four minutes; routing it over the pavement
// above would be both longer and wrong.
//
// Bus station groups are deliberately not emitted, though the data is landed and
// the idea is tempting. Those are stops a few metres apart on a street, which is
// exactly what a router's own footpath computation over OSM is good at, and the
// volume is prohibitive: the largest group holds 151 stops, and even capped at
// eight members per group the stop-level pairs come to 240,118 rows. That is a
// large feed for something the router already does better with real geometry.
//
// Rows are attached to the station rather than the platform, so the rule applies
// to every platform beneath it. A transfer naming a station the feed does not
// carry is dropped: TDX states ten whose destination is absent from
// Metro/Station, and a dangling reference is a validator error.
//
// The direction TDX states is the direction emitted. Thirty-one of the
// forty-one rows already carry their reverse, and synthesising the rest would
// assert a symmetry that platform layouts do not always have.
var gtfsTransfersSQL = `
SELECT
  t.system || ':' || t.fromstationid AS from_stop_id,
  t.system || ':' || t.tostationid AS to_stop_id,
  -- 2: the transfer is possible but needs the stated time.
  2 AS transfer_type,
  t.transfertime * 60 AS min_transfer_time
FROM raw_tdx.metro_linetransfer t
WHERE t.transfertime > 0
  AND t.fromstationid <> t.tostationid
  AND EXISTS (SELECT 1 FROM (` + metroPatternSQL + `) p
              WHERE p.complete AND p.system = t.system AND p.station_id = t.fromstationid)
  AND EXISTS (SELECT 1 FROM (` + metroPatternSQL + `) p
              WHERE p.complete AND p.system = t.system AND p.station_id = t.tostationid)
ORDER BY from_stop_id, to_stop_id`

// gtfsShapesSQL emits the drawn path of each route.
//
// Geometry is passed through unsimplified. It was briefly reduced with a
// five-metre Douglas-Peucker tolerance, which cut 6,044,458 points to 1,500,775,
// on the argument that five metres is sub-pixel on a map. That argument is
// wrong: this file exists to be drawn, a rider zoomed to street level can see
// five metres, and TDX's own sampling precision is unknown — degrading it a
// second time is not ours to do. Disk and build time are the cheap side of that
// trade.
//
// Bus geometry keyed by subroute and direction, and metro by line. Both are
// assignable to a trip: a bus trip runs one subroute in one direction, and a
// metro route belongs to one line.
//
// TRA and THSR are absent. rail_shapes is keyed by line, but a train crosses
// lines freely — a 自強 runs the 西部幹線 into the 南迴線 — so no single shape
// describes a train's path, and stitching them per trip is a different job from
// this one. Their trips carry no shape_id, which GTFS permits; a planner draws
// straight lines between their stops.
//
// A trip claims a shape only when one exists, checked on the trips side. The
// check has to live in exactly one place: when both files filtered independently
// they disagreed — shapes.txt considered only the daily-timetable trips while
// trips.txt also emitted the weekly-schedule ones — and 14,334 trips pointed at
// shapes that were never written.
//
// Bus rows with no SubRouteUID apply to every subroute of the route. They are
// skipped rather than fanned out: the fan-out would repeat a few thousand points
// per subroute for geometry that is already approximate, and a missing shape
// costs only a straight line on a map.
var gtfsShapesSQL = `
WITH shape AS (
  SELECT
    'B:' || s.subrouteuid || ':' || COALESCE(s.direction, 0)::text AS shape_id,
    ST_GeomFromText(s.geometry, 4326) AS geom
  FROM raw_tdx.bus_shape s
  WHERE COALESCE(s.subrouteuid, '') <> ''
    AND s.geometry LIKE 'LINESTRING%'
    -- Some trip has to be able to point at it, and every bus source has to be
    -- checked. Filtering against a subset is how this breaks: two sources left
    -- 14,334 trips pointing at shapes that were never written, and adding the
    -- pattern source without adding it here left another 1,410. A new bus source
    -- belongs in this list on the same commit that introduces it.
    AND (EXISTS (SELECT 1 FROM (` + busScheduleSource + `) w
                 WHERE split_part(w.trip_id, ':', 1) = s.subrouteuid
                   AND w.direction_id = COALESCE(s.direction, 0))
      OR EXISTS (SELECT 1 FROM (` + busOriginTripSource + `) o
                 WHERE o.subrouteuid = s.subrouteuid
                   AND o.direction_id = COALESCE(s.direction, 0)))
  UNION ALL
  SELECT
    'M:' || m.system || ':' || m.lineid,
    ST_GeomFromText(m.geometry, 4326)
  FROM raw_tdx.metro_shape m
  WHERE COALESCE(m.lineid, '') <> '' AND m.geometry LIKE 'LINESTRING%'
), deduped AS (
  SELECT DISTINCT ON (shape_id) shape_id, geom FROM shape ORDER BY shape_id, ST_NPoints(geom) DESC
)
SELECT
  d.shape_id,
  ST_Y(p.geom)::numeric(9,6) AS shape_pt_lat,
  ST_X(p.geom)::numeric(9,6) AS shape_pt_lon,
  p.path[1] AS shape_pt_sequence
FROM deduped d
CROSS JOIN LATERAL ST_DumpPoints(d.geom) p
WHERE ST_Y(p.geom) BETWEEN 21 AND 26.5 AND ST_X(p.geom) BETWEEN 118 AND 122.5
ORDER BY d.shape_id, p.path[1]`
