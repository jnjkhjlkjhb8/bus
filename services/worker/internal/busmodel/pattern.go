package busmodel

// busPatternSQL is the ordered stop list of every bus route direction, each stop
// carrying its cumulative seconds from the origin.
//
// complete is the same all-or-nothing judgement metroPatternSQL makes, and for
// the same reason: a journey is laid out by accumulating hops, so one unknown
// segment silently compresses everything after it and the direction has to be
// dropped rather than published wrong. The stop_count guard is the other half —
// a route direction with a single stop has no hops to miss, so it would pass a
// pure BOOL_AND and produce a trip that never moves.
//
// The known_stop test is the third: bus_station_stop_map carries stops that
// bus_stopofroute does not, so stops.txt never declares them — TNN33591 is on
// four Tainan directions and in no stop inventory. Emitting a call there is a
// dangling reference, which is an invalid feed rather than a merely thin one.
// The stop cannot simply be skipped either: dropping it from the middle of a
// sequence makes the surrounding running times describe a journey that omits a
// stop the bus actually serves. So the direction goes, exactly as it does for a
// missing segment.
const PatternSQL = `
  WITH known_stop AS (
    SELECT DISTINCT c->>'StopUID' AS stop_uid
    FROM raw_tdx.bus_stopofroute s
    CROSS JOIN LATERAL jsonb_array_elements(s.stops) c
    WHERE jsonb_typeof(s.stops) = 'array' AND COALESCE(c->>'StopUID', '') <> ''
  ), linked AS (
    SELECT m.sub_route_uid, m.direction, m.stop_uid, m.stop_sequence,
           LAG(m.stop_uid) OVER w AS prev_stop_uid,
           count(*) OVER (PARTITION BY m.sub_route_uid, m.direction) AS stop_count
    FROM bus_station_stop_map m
    WINDOW w AS (PARTITION BY m.sub_route_uid, m.direction ORDER BY m.stop_sequence)
  )
  SELECT l.sub_route_uid, l.direction, l.stop_sequence, l.stop_uid,
         SUM(COALESCE(g.secs, 0)) OVER (PARTITION BY l.sub_route_uid, l.direction
                                        ORDER BY l.stop_sequence
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS offset_secs,
         (l.stop_count > 1
          AND BOOL_AND(l.prev_stop_uid IS NULL OR g.secs IS NOT NULL)
              OVER (PARTITION BY l.sub_route_uid, l.direction)
          AND BOOL_AND(k.stop_uid IS NOT NULL)
              OVER (PARTITION BY l.sub_route_uid, l.direction)) AS complete
  FROM linked l
  LEFT JOIN known_stop k ON k.stop_uid = l.stop_uid
  LEFT JOIN bus_segment_time g
    ON g.sub_route_uid = l.sub_route_uid
   AND g.direction     = l.direction
   AND g.from_stop_uid = l.prev_stop_uid
   AND g.to_stop_uid   = l.stop_uid`
