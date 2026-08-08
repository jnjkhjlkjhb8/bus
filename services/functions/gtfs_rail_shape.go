package main

import "strconv"

// Rail geometry for the GTFS feed: the drawn path of a TRA or THSR trip.
//
// rail_shapes holds one geometry per line, and a train crosses lines freely — a
// 自強 runs the 西部幹線 into the 南迴線 — so no stored geometry describes a
// train's path. It is assembled here instead: a trip's path is decided by the
// stops it calls at, so every train sharing a stop sequence shares one shape,
// built by clipping the line geometry between each consecutive pair of stops
// and stitching the clips together.
//
// This is the same construction the router runs per MaaS section
// (services/router/maas_geometry.go). It is not shared code: that one clips one
// stop pair at a time with bind parameters, this one clips every distinct pair
// in the feed in a single set-based pass, and the two statements have no useful
// overlap beyond the idea. The tolerances below are the ones to keep in step.

const (
	// railShapeSnapMeters is how far a station may sit from a line before that
	// line is rejected as the one it is served by. Matches the router's constant
	// of the same name: 500 m tolerates the walk-in access point TDX reports for
	// some stations without matching an unrelated line.
	railShapeSnapMeters = 500
	// railShapeSimplifyTolerance is the ST_SimplifyPreserveTopology tolerance, in
	// degrees (~11 m), applied to each clipped segment.
	//
	// shapes.txt passes bus and metro geometry through unsimplified, and rail is
	// the exception on purpose: those two emit each stored geometry once, while a
	// rail segment is re-emitted in every stop sequence that traverses it —
	// thousands of them — so density that costs a bus shape a few thousand points
	// costs the feed millions. The tolerance is the router's, which is already
	// what the app draws this same geometry with.
	railShapeSimplifyTolerance = 0.0001
)

// railShapeSnapMetersSQL and railShapeSimplifyToleranceSQL are the constants in
// the form the statements below can splice.
var (
	railShapeSnapMetersSQL        = strconv.Itoa(railShapeSnapMeters)
	railShapeSimplifyToleranceSQL = strconv.FormatFloat(railShapeSimplifyTolerance, 'f', -1, 64)
)

// gtfsRailSegSQL clips one rail line between every distinct pair of
// consecutive stops the feed's rail trips call at.
//
// Matching is geometric, as the router's is: the daily timetable names no line,
// only stations. A candidate is a component of a merged line geometry that both
// stops sit within railShapeSnapMeters of, and the best candidate is the one
// minimising the larger of the two distances. Requiring both stops on the same
// component is what keeps a junction station from matching the line its
// neighbour is not on.
//
// Distances are computed per station rather than per pair. There are a few
// hundred stations and a few thousand pairs, and the pair count is what would
// multiply the cost of measuring a point against a line of a hundred thousand
// vertices.
//
// ST_LineSubstring needs a simple LINESTRING, hence the dump; the fractions are
// ordered low-to-high because the pair's travel direction need not match the
// line's digitized direction, and the substring is reversed back into travel
// order afterwards so the stitched shape runs the way the train does.
var gtfsRailSegSQL = `
WITH rail_stop AS (
  SELECT s.stop_id,
         CASE WHEN s.stop_id LIKE 'TRA:%' THEN 'tra' ELSE 'thsr' END AS mode,
         ST_SetSRID(ST_MakePoint(s.stop_lon, s.stop_lat), 4326) AS pt
  FROM ` + gtfsStopTable + ` s
  WHERE s.location_type = 0
    AND (s.stop_id LIKE 'TRA:%' OR s.stop_id LIKE 'THSR:%')
), component AS (
  -- One line may be several components: ST_LineMerge leaves a branch or a gap
  -- as its own piece, and only a single piece can be located along.
  SELECT sh.mode, sh.line_id, d.path[1] AS part, d.geom
  FROM rail_shapes sh
  CROSS JOIN LATERAL ST_Dump(ST_LineMerge(sh.geom)) d
  WHERE sh.mode IN ('tra', 'thsr')
    AND ST_GeometryType(d.geom) = 'ST_LineString'
), snapped AS (
  SELECT rs.stop_id, c.line_id, c.part, c.geom,
         ST_Distance(c.geom::geography, rs.pt::geography) AS dist,
         ST_LineLocatePoint(c.geom, rs.pt) AS frac
  FROM rail_stop rs
  JOIN component c ON c.mode = rs.mode
), near AS (
  SELECT * FROM snapped WHERE dist <= ` + railShapeSnapMetersSQL + `
), pair AS (
  SELECT DISTINCT from_stop, to_stop
  FROM (
    SELECT st.stop_id AS from_stop,
           LEAD(st.stop_id) OVER (PARTITION BY st.trip_id ORDER BY st.stop_sequence) AS to_stop
    FROM ` + gtfsStopTimeTable + ` st
    WHERE st.trip_id LIKE 'TRA:%' OR st.trip_id LIKE 'THSR:%'
  ) s
  WHERE to_stop IS NOT NULL
), matched AS (
  SELECT DISTINCT ON (p.from_stop, p.to_stop)
    p.from_stop, p.to_stop, a.geom, a.frac AS f1, b.frac AS f2
  FROM pair p
  JOIN near a ON a.stop_id = p.from_stop
  JOIN near b ON b.stop_id = p.to_stop AND b.line_id = a.line_id AND b.part = a.part
  ORDER BY p.from_stop, p.to_stop, GREATEST(a.dist, b.dist)
)
SELECT
  from_stop,
  to_stop,
  ST_SimplifyPreserveTopology(
    CASE WHEN f1 <= f2 THEN ST_LineSubstring(geom, f1, f2)
         ELSE ST_Reverse(ST_LineSubstring(geom, f2, f1)) END,
    ` + railShapeSimplifyToleranceSQL + `) AS geom
FROM matched
-- Two stops that locate onto the same point of a line would clip to a single
-- point, which is not a segment. The stitch falls back to a straight line.
WHERE f1 <> f2`

// gtfsRailTripShapeSQL names the shape each rail trip draws.
//
// The id is the digest of the stop sequence, so the thousands of trains running
// the same calls share one shape rather than repeating its geometry per train
// per date. The operator is kept in the clear so a shape can be read.
//
// This mapping is the single place a rail trip and its shape are decided: both
// trips.txt and shapes.txt read it, which is what stops them from disagreeing
// about which shapes exist — the failure the bus branch already learned, where
// two independent filters left 14,334 trips pointing at shapes never written.
//
// A trip with one call has no path to draw and gets no shape. Neither does one
// calling anywhere stops.txt has no coordinates for: the shape is drawn between
// stop positions, so a trip missing one has legs that cannot be built, and a
// shape claimed by a trip has to be a shape shapes.txt writes.
var gtfsRailTripShapeSQL = `
SELECT
  st.trip_id,
  'R:' || split_part(st.trip_id, ':', 1) || ':' ||
    md5(string_agg(st.stop_id, '>' ORDER BY st.stop_sequence)) AS shape_id
FROM ` + gtfsStopTimeTable + ` st
LEFT JOIN ` + gtfsStopTable + ` s ON s.stop_id = st.stop_id
WHERE st.trip_id LIKE 'TRA:%' OR st.trip_id LIKE 'THSR:%'
GROUP BY st.trip_id
HAVING count(*) > 1 AND count(*) = count(s.stop_id)`

// gtfsRailShapePointsSQL is the rail branch of shapes.txt: each shape's stitched
// points, in travel order.
//
// One representative trip per shape supplies the call order; every other trip
// with that shape calls at the same stops in the same order, which is what the
// id says.
//
// A pair with no clipped segment contributes the straight line between its two
// stops rather than nothing, so one unmatched pair costs a shape one straight
// leg instead of leaving a gap in it — the same degradation the router's
// transit path makes.
//
// Each leg after the first drops its own first point: it is the joint with the
// previous leg's last point, and emitting both would repeat a coordinate at
// every intermediate station.
var gtfsRailShapePointsSQL = `
SELECT
  leg.shape_id,
  ST_Y(p.geom)::numeric(9,6) AS shape_pt_lat,
  ST_X(p.geom)::numeric(9,6) AS shape_pt_lon,
  (ROW_NUMBER() OVER (PARTITION BY leg.shape_id ORDER BY leg.leg_no, p.path[1]))::int
    AS shape_pt_sequence
FROM (
  SELECT
    s.shape_id,
    ROW_NUMBER() OVER (PARTITION BY s.shape_id ORDER BY s.stop_sequence) AS leg_no,
    COALESCE(
      g.geom,
      ST_MakeLine(ST_SetSRID(ST_MakePoint(a.stop_lon, a.stop_lat), 4326),
                  ST_SetSRID(ST_MakePoint(b.stop_lon, b.stop_lat), 4326))) AS geom
  FROM (
    SELECT r.shape_id, st.stop_sequence, st.stop_id AS from_stop,
           LEAD(st.stop_id) OVER (PARTITION BY r.shape_id ORDER BY st.stop_sequence) AS to_stop
    FROM (
      SELECT DISTINCT ON (shape_id) shape_id, trip_id
      FROM ` + gtfsRailTripShapeTable + `
      ORDER BY shape_id, trip_id
    ) r
    JOIN ` + gtfsStopTimeTable + ` st ON st.trip_id = r.trip_id
  ) s
  JOIN ` + gtfsStopTable + ` a ON a.stop_id = s.from_stop
  JOIN ` + gtfsStopTable + ` b ON b.stop_id = s.to_stop
  LEFT JOIN ` + gtfsRailSegTable + ` g
    ON g.from_stop = s.from_stop AND g.to_stop = s.to_stop
  WHERE s.to_stop IS NOT NULL
) leg
CROSS JOIN LATERAL ST_DumpPoints(leg.geom) p
WHERE (leg.leg_no = 1 OR p.path[1] > 1)
  AND ST_Y(p.geom) BETWEEN 21 AND 26.5
  AND ST_X(p.geom) BETWEEN 118 AND 122.5`
