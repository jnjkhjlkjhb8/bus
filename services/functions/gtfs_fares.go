package main

// GTFS fare files (Fares v2): areas, stop_areas, fare_products, fare_leg_rules
// and the per-network fare tables they price from. Split out of gtfs_files.go
// for size; that file documents the identifier scheme every statement assumes.

// ---------------------------------------------------------------------------
// Fares (GTFS-Fares v2).
// ---------------------------------------------------------------------------

// The temp tables gtfsTempTables materializes, named where the queries read
// them. They exist only inside the export transaction, so every statement below
// is one a bare psql session cannot run on its own — createGTFSTempTables comes
// first, and TestGTFSStatementsPlan proves the set is closed.
const (
	gtfsStopTable       = "gtfs_stop"
	gtfsStopTimeTable   = "gtfs_stop_time"
	gtfsFareSrcTable    = "gtfs_fare_src"
	gtfsStopUIDTable    = "gtfs_stop_uid"
	gtfsStopSeqTable    = "gtfs_stop_seq"
	gtfsFarePairTable   = "gtfs_fare_pair"
	gtfsFareLegTable    = "gtfs_fare_leg"
	gtfsFarePricedTable = "gtfs_fare_priced"
	gtfsFareZoneTable   = "gtfs_fare_zone"
)

// gtfsFareODSQL is every station-to-station fare the feed prices, flattened to
// one row per (network, origin station, destination station, amount).
//
// One adult single fare per pair, per mode. Fares v2 can carry the rider and
// media axes as well, and TDX has them, but every extra axis multiplies the leg
// rules by a factor and none of them is what a planner compares journeys on.
// The axes are pinned to the same values services/router/maas.go pins for its
// own fare quotes, so a fare quoted in the app and a fare in the feed agree:
//
//	metro  TicketType 1 (單程), FareClass 1 (全票)
//	THSR   TicketType 1 (單程), FareClass 1 (全票), cheapest cabin (標準車廂)
//	TRA    ticket type 成復
//
// The TRA choice is worth stating plainly: TDX prices a pair once per train
// class (成自/成莒/成復/成普) and GTFS routes for TRA are train types, so a
// per-class network would be more accurate. 成復 is used because it is the only
// class present for every pair, and because taking anything else diverges from
// what the app already quotes — maas.go's comment records that taking the max
// instead quoted 自強 on every leg (桃園→臺北: 99 rather than 63). A 自強 leg is
// therefore under-priced here (FDPL: per-train-class TRA fare networks).
const gtfsFareODSQL = `
  SELECT 'MRT:' || f.system AS network_id,
         f.system || ':' || f.originstationid AS from_stop,
         f.system || ':' || f.destinationstationid AS to_stop,
         MIN((t.value->>'Price')::int) AS amount
  FROM raw_tdx.metro_odfare f
  CROSS JOIN LATERAL jsonb_array_elements(f.fares) t
  WHERE jsonb_typeof(f.fares) = 'array'
    AND COALESCE(f.originstationid, '') <> ''
    AND COALESCE(f.destinationstationid, '') <> ''
    AND (t.value->>'TicketType')::int = 1
    AND (t.value->>'FareClass')::int = 1
    AND (t.value->>'Price') ~ '^[0-9]+$'
  GROUP BY 1, 2, 3
  UNION ALL
  SELECT 'THSR',
         'THSR:' || f.originstationid,
         'THSR:' || f.destinationstationid,
         MIN((t.value->>'Price')::int)
  FROM raw_tdx.thsr_odfare f
  CROSS JOIN LATERAL jsonb_array_elements(f.fares) t
  WHERE jsonb_typeof(f.fares) = 'array'
    AND COALESCE(f.originstationid, '') <> ''
    AND COALESCE(f.destinationstationid, '') <> ''
    AND (t.value->>'TicketType')::int = 1
    AND (t.value->>'FareClass')::int = 1
    AND (t.value->>'Price') ~ '^[0-9]+$'
  GROUP BY 1, 2, 3
  UNION ALL
  SELECT 'TRA',
         'TRA:' || f.originstationid,
         'TRA:' || f.destinationstationid,
         MIN((t.value->>'Price')::int)
  FROM raw_tdx.tra_odfare f
  CROSS JOIN LATERAL jsonb_array_elements(f.fares) t
  WHERE jsonb_typeof(f.fares) = 'array'
    AND COALESCE(f.originstationid, '') <> ''
    AND COALESCE(f.destinationstationid, '') <> ''
    AND t.value->>'TicketType' = '成復'
    AND (t.value->>'Price') ~ '^[0-9]+$'
  GROUP BY 1, 2, 3`

// gtfsFarePricedSQL is gtfsFareODSQL restricted to the pairs both of whose
// stations the feed actually emits, with the area ids the fare files use.
//
// The restriction is the whole point. TDX prices every station pair it knows,
// including systems with no landed timetable, and a leg rule naming an area that
// stop_areas never declares is a broken feed rather than a generous one. Joining
// against gtfsStopsSQL rather than against a second copy of its filters is what
// keeps that true when the stop query changes.
//
// A station's area holds both the station node and its platform: stop_times
// references the platform, but a consumer that resolves a leg to the parent
// station should match the same area.
// The stop query is named once and referenced twice rather than inlined twice:
// working out which stops are served scans stop_times, and every needless copy
// of gtfsStopsSQL in a fare file is that scan again.
//
// A leg priced at zero is dropped here but not from the flat rules: on a station
// pair zero means TDX stated no fare, while a free bus states zero and means it.
var gtfsFarePricedSQL = `
  WITH leg AS (
    SELECT network_id, from_stop, to_stop, amount FROM (` + gtfsFareODSQL + `) rail
    UNION ALL
    SELECT network_id, from_uid, to_uid, amount
    FROM ` + gtfsFareLegTable + ` bus
    WHERE from_uid IS NOT NULL AND to_uid IS NOT NULL
  )
  SELECT leg.network_id,
         'A:' || leg.from_stop AS from_area_id,
         'A:' || leg.to_stop AS to_area_id,
         leg.amount
  FROM leg
  WHERE leg.amount > 0
    AND leg.from_stop <> leg.to_stop
    AND leg.from_stop IN (SELECT stop_id FROM ` + gtfsStopTable + `)
    AND leg.to_stop   IN (SELECT stop_id FROM ` + gtfsStopTable + `)`

// gtfsFareFlatSQL prices the routes that charge one fare however far the rider
// goes. Both area fields empty is Fares v2's way of saying "any leg on this
// network".
var gtfsFareFlatSQL = `
  SELECT network_id, '' AS from_area_id, '' AS to_area_id, amount
  FROM ` + gtfsFareLegTable + ` flat
  WHERE from_uid IS NULL AND amount >= 0`

// gtfsFareZoneSQL is busSectionZoneSQL restricted to stops the feed emits, so a
// zone that survives has something in it.
var gtfsFareZoneSQL = `
  SELECT z.routeuid, z.unit, z.stop_uid, z.idx
  FROM (` + busSectionZoneSQL + `) z
  WHERE z.stop_uid IN (SELECT stop_id FROM ` + gtfsStopTable + `)`

// gtfsFareZoneMembersSQL is which stops each section zone holds.
//
// Unlike the per-stop areas, a zone's membership cannot be read back out of its
// id, so stop_areas.txt takes it from here.
var gtfsFareZoneMembersSQL = `
  SELECT DISTINCT 'Z:' || z.routeuid || ':' || z.idx::text AS area_id, z.stop_uid AS stop_id
  FROM ` + gtfsFareZoneTable + ` z`

// gtfsFareZoneRulesSQL prices a sectioned leg: one unit per section entered.
//
//	sections entered = 1 + buffer zones the leg crosses entirely
//
// A buffer zone sits at every odd index, so the zones a leg from index i to
// index j crosses are the odd numbers strictly between them, which is
// j/2 - (i+1)/2 in integer division. Riding into a buffer costs nothing extra —
// that is what makes it a buffer — and only passing clear through it adds a
// unit.
//
// GREATEST clamps the one case that expression gets wrong: when i and j are the
// same odd index the range it counts over runs backwards and it returns -1,
// which priced a ride that begins and ends inside one buffer zone at nothing.
var gtfsFareZoneRulesSQL = `
  WITH zone AS (SELECT DISTINCT routeuid, unit, idx FROM ` + gtfsFareZoneTable + ` z)
  SELECT 'BUS:' || a.routeuid AS network_id,
         'Z:' || a.routeuid || ':' || a.idx::text AS from_area_id,
         'Z:' || a.routeuid || ':' || b.idx::text AS to_area_id,
         ` + busSectionUnitsSQL("a.idx", "b.idx") + ` * a.unit AS amount
  FROM zone a
  JOIN zone b ON b.routeuid = a.routeuid AND b.idx >= a.idx`

// busSectionUnitsSQL is how many section fares a leg from one zone index to
// another costs. Pulled out of the query so TestGTFSSectionFareUnits can
// evaluate the same expression the feed does rather than a copy of it.
func busSectionUnitsSQL(from, to string) string {
	return `(GREATEST(` + to + ` / 2 - (` + from + ` + 1) / 2, 0) + 1)`
}

// gtfsFareAllRulesSQL is every priced leg: per-pair, sectioned and flat alike.
var gtfsFareAllRulesSQL = `
  SELECT network_id, from_area_id, to_area_id, amount FROM ` + gtfsFarePricedTable + ` p
  UNION ALL
  SELECT network_id, from_area_id, to_area_id, amount FROM (` + gtfsFareZoneRulesSQL + `) z
  UNION ALL
  SELECT network_id, from_area_id, to_area_id, amount FROM (` + gtfsFareFlatSQL + `) f`

// gtfsAreasSQL declares every fare area: one per priced stop, plus one per
// section zone.
var gtfsAreasSQL = `
WITH priced AS (SELECT * FROM ` + gtfsFarePricedTable + `)
SELECT DISTINCT area_id, '' AS area_name
FROM (
  SELECT from_area_id AS area_id FROM priced
  UNION
  SELECT to_area_id FROM priced
  UNION
  SELECT area_id FROM (` + gtfsFareZoneMembersSQL + `) z
) x
ORDER BY area_id`

// gtfsStopAreasSQL puts each priced stop in its own area and each sectioned
// route's stops in their zone's.
//
// An 'A:' area's membership is its id: the stop, and its platform when the stop
// is a station. A 'Z:' area's is not, so it comes from the zone assignment.
var gtfsStopAreasSQL = `
WITH area AS (
  SELECT from_area_id AS area_id FROM ` + gtfsFarePricedTable + `
  UNION
  SELECT to_area_id FROM ` + gtfsFarePricedTable + `
)
SELECT area.area_id, s.stop_id
FROM area
JOIN ` + gtfsStopTable + ` s
  ON s.stop_id IN (substring(area.area_id from 3),
                   substring(area.area_id from 3) || ':platform')
UNION
SELECT area_id, stop_id FROM (` + gtfsFareZoneMembersSQL + `) z
ORDER BY area_id, stop_id`

// busFareSourceSQL is every bus fare this feed can express, as one row per route
// per priced leg, before it is decided whether the route needs areas.
//
// TDX states a bus fare four ways and this reads three of them:
//
//	IsFreeBus            345 records   a column, price 0
//	SectionFares         1,821         one price plus BufferZones marking where
//	                                   a section changes. 1,143 have no zones at
//	                                   all, which is a single-section route: a
//	                                   flat fare.
//	ODFares              1,014         OriginStop/DestinationStop by StopID
//	StageFares           2,477         OriginStage/DestinationStage, also stops
//
// The 678 section records that do carry BufferZones are not read. Fares v2 has
// no way to say "pay one section fare per section boundary crossed" without
// modelling every boundary as an area and every crossing as a transfer rule,
// and inventing that from a description field is how a rider gets quoted a fare
// they will not be charged (FDPL: price sectioned bus fares).
//
// from_id/to_id NULL means the price applies to any leg on the route.
//
// Price is filtered to digits: StageFares uses -1 for "no fare stated", which
// would otherwise become a negative fare product.
const busFareSourceSQL = `
  SELECT f.city, f.routeid, NULL::text AS from_id, NULL::text AS to_id, 0 AS amount
  FROM raw_tdx.bus_routefare f
  WHERE COALESCE(f.isfreebus, 0) = 1
  UNION ALL
  -- A section fare with no buffer zone anywhere is one section, so one price.
  SELECT f.city, f.routeid, NULL, NULL, MIN((p.value->>'Price')::int)
  FROM raw_tdx.bus_routefare f
  CROSS JOIN LATERAL jsonb_array_elements(f.sectionfares) e
  CROSS JOIN LATERAL jsonb_array_elements(e.value->'Fares') p
  WHERE jsonb_typeof(f.sectionfares) = 'array'
    AND jsonb_typeof(e.value->'Fares') = 'array'
    AND COALESCE(f.isfreebus, 0) <> 1
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(f.sectionfares) z
      WHERE jsonb_typeof(z.value->'BufferZones') = 'array'
        AND jsonb_array_length(z.value->'BufferZones') > 0
    )
    AND ` + busFareAdultSQL + `
  GROUP BY 1, 2
  UNION ALL
  SELECT f.city, f.routeid,
         e.value->'OriginStop'->>'StopID',
         e.value->'DestinationStop'->>'StopID',
         MIN((p.value->>'Price')::int)
  FROM raw_tdx.bus_routefare f
  CROSS JOIN LATERAL jsonb_array_elements(f.odfares) e
  CROSS JOIN LATERAL jsonb_array_elements(e.value->'Fares') p
  WHERE jsonb_typeof(f.odfares) = 'array'
    AND jsonb_typeof(e.value->'Fares') = 'array'
    AND COALESCE(e.value->'OriginStop'->>'StopID', '') <> ''
    AND COALESCE(e.value->'DestinationStop'->>'StopID', '') <> ''
    AND ` + busFareAdultSQL + `
  GROUP BY 1, 2, 3, 4
  UNION ALL
  SELECT f.city, f.routeid,
         e.value->'OriginStage'->>'StopID',
         e.value->'DestinationStage'->>'StopID',
         MIN((p.value->>'Price')::int)
  FROM raw_tdx.bus_routefare f
  CROSS JOIN LATERAL jsonb_array_elements(f.stagefares) e
  CROSS JOIN LATERAL jsonb_array_elements(e.value->'Fares') p
  WHERE jsonb_typeof(f.stagefares) = 'array'
    AND jsonb_typeof(e.value->'Fares') = 'array'
    AND COALESCE(e.value->'OriginStage'->>'StopID', '') <> ''
    AND COALESCE(e.value->'DestinationStage'->>'StopID', '') <> ''
    AND ` + busFareAdultSQL + `
  GROUP BY 1, 2, 3, 4`

// busSectionZoneSQL assigns every stop of a section-priced route to one zone.
//
// A Taiwanese sectioned fare is one unit price charged once per section entered,
// and the sections are separated by buffer zones rather than by points: TDX gives
// each zone a FareBufferZoneOrigin and a FareBufferZoneDestination, and a rider
// travelling wholly inside one pays a single unit. So a route with k buffer zones
// splits into 2k+1 zones — k+1 cores with the k buffers between them — and every
// stop falls in exactly one:
//
//	[core 0][buffer 1][core 1][buffer 2][core 2]
//	   0        1        2        3        4
//
//	idx = 2 * (buffer zones ending before the stop) + (1 if inside one)
//
// That indexing is the whole trick. Splitting at points instead would put a
// buffer's stops in the sections on both sides, two leg rules would match one
// leg, and Fares v2 does not say which wins.
//
// Measured 2026-08-01: 678 fare records over 455 routes carry buffer zones,
// averaging 2.7 zones each, and all 1,216 zone endpoints resolve to a stop on
// their own subroute.
// busStopSeqSQL is every subroute's stop list with the sequence the section
// zones are laid out along. It is materialized (gtfsTempTables) because
// busSectionZoneSQL joins to it three times — the two ends of every buffer zone,
// then every stop to be placed between them.
const busStopSeqSQL = `
    SELECT r.city, r.subrouteuid, COALESCE(r.direction, 0) AS direction,
           s->>'StopUID' AS stop_uid, s->>'StopID' AS stop_id,
           (s->>'StopSequence')::int AS seq
    FROM raw_tdx.bus_stopofroute r
    CROSS JOIN LATERAL jsonb_array_elements(r.stops) s
    WHERE jsonb_typeof(r.stops) = 'array'
      AND COALESCE(s->>'StopUID', '') <> ''
      AND (s->>'StopSequence') ~ '^[0-9]+$'`

const busSectionZoneSQL = `
  WITH rec AS (
    SELECT f.city, f.routeid, f.subrouteid,
           MIN((p.value->>'Price')::int) AS unit,
           e.value->'BufferZones' AS zones
    FROM raw_tdx.bus_routefare f
    CROSS JOIN LATERAL jsonb_array_elements(f.sectionfares) e
    CROSS JOIN LATERAL jsonb_array_elements(e.value->'Fares') p
    WHERE jsonb_typeof(f.sectionfares) = 'array'
      AND jsonb_typeof(e.value->'BufferZones') = 'array'
      AND jsonb_array_length(e.value->'BufferZones') > 0
      AND jsonb_typeof(e.value->'Fares') = 'array'
      AND COALESCE(f.isfreebus, 0) <> 1
      AND ` + busFareAdultSQL + `
    GROUP BY 1, 2, 3, 5
  ), sub AS (
    SELECT DISTINCT r.city, r.routeuid,
           s->>'SubRouteID' AS subrouteid, s->>'SubRouteUID' AS subrouteuid
    FROM raw_tdx.bus_route r
    CROSS JOIN LATERAL jsonb_array_elements(r.subroutes) s
    WHERE jsonb_typeof(r.subroutes) = 'array'
      AND COALESCE(s->>'SubRouteID', '') <> ''
      AND COALESCE(s->>'SubRouteUID', '') <> ''
  ), buffer AS (
    SELECT sub.routeuid, sub.subrouteuid, o.direction, rec.unit,
           o.seq AS lo, d.seq AS hi
    FROM rec
    JOIN sub ON sub.city = rec.city AND sub.subrouteid = rec.subrouteid
    CROSS JOIN LATERAL jsonb_array_elements(rec.zones) z
    JOIN ` + gtfsStopSeqTable + ` o ON o.city = rec.city AND o.subrouteuid = sub.subrouteuid
                AND o.direction = (z.value->>'Direction')::int
                AND o.stop_id = z.value->'FareBufferZoneOrigin'->>'StopID'
    JOIN ` + gtfsStopSeqTable + ` d ON d.city = rec.city AND d.subrouteuid = sub.subrouteuid
                AND d.direction = o.direction
                AND d.stop_id = z.value->'FareBufferZoneDestination'->>'StopID'
    WHERE o.seq <= d.seq
  ), zoned AS (
    SELECT b.routeuid, b.unit, s.stop_uid,
           2 * count(*) FILTER (WHERE b.hi < s.seq)
             + CASE WHEN count(*) FILTER (WHERE s.seq BETWEEN b.lo AND b.hi) > 0
                    THEN 1 ELSE 0 END AS idx
    FROM buffer b
    JOIN ` + gtfsStopSeqTable + ` s ON s.subrouteuid = b.subrouteuid AND s.direction = b.direction
    GROUP BY b.routeuid, b.unit, b.subrouteuid, b.direction, s.stop_uid, s.seq
  ), conflict AS (
    -- A stop landing on two indices means two subroutes or two directions of one
    -- route disagree about which section it is in, and a GTFS area carries
    -- neither. 10,077 of 153,801 bus stops nationally serve both directions, so
    -- this is a real case rather than a defensive one. The route is dropped
    -- whole: pricing the half that agrees would quote some legs and not others
    -- on the same route, which reads as "this leg is free".
    SELECT DISTINCT routeuid FROM (
      SELECT routeuid, stop_uid FROM zoned GROUP BY 1, 2 HAVING count(DISTINCT idx) > 1
    ) c
    UNION
    SELECT routeuid FROM zoned GROUP BY routeuid HAVING count(DISTINCT unit) > 1
  )
  SELECT z.routeuid, z.unit, z.stop_uid, z.idx
  FROM zoned z
  WHERE z.routeuid NOT IN (SELECT routeuid FROM conflict)`

// busFareAdultSQL pins the rider axis to the full adult single, the same axis
// the rail fares pin. FareClass 1 is 全票 in every bus pricing type; the classes
// beside it are 半票 and the concession tiers.
const busFareAdultSQL = `(p.value->>'TicketType')::int = 1
    AND (p.value->>'FareClass')::int = 1
    AND (p.value->>'Price') ~ '^[0-9]+$'`

// busStopUIDSQL maps TDX's city-local StopID to the StopUID stop_times
// references. It is materialized (gtfsTempTables) because the fare legs join to
// it twice, once per endpoint, over 1.8M rows.
const busStopUIDSQL = `
    SELECT DISTINCT r.city, s->>'StopID' AS stop_id, s->>'StopUID' AS stop_uid
    FROM raw_tdx.bus_stopofroute r
    CROSS JOIN LATERAL jsonb_array_elements(r.stops) s
    WHERE jsonb_typeof(r.stops) = 'array'
      AND COALESCE(s->>'StopID', '') <> ''
      AND COALESCE(s->>'StopUID', '') <> ''`

// busFareLegSQL resolves bus fares onto the ids the feed uses, and collapses a
// route whose every leg costs the same into one rule.
//
// The collapse is not an optimisation detail, it is what makes bus fares fit.
// ODFares and StageFares state a price per stop pair: 1,644,378 and 367,045
// adult rows respectively. Emitted verbatim that is two million leg rules for a
// country where most bus routes charge one fare end to end. A route whose prices
// are all one value is stated once, with empty areas, and only a route that
// genuinely varies pays for its pairs.
//
// StopID is TDX's city-local id and stop_times references StopUID, so the pair
// rows are mapped through bus_stopofroute, which carries both.
// busFarePairSQL is one row per priced leg with both ends resolved onto the ids
// the feed uses. It is materialized (gtfsTempTables) because busFareLegSQL joins
// it to itself twice — a leg to its reverse, then a route to its verdict — over
// 1.75M rows.
var busFarePairSQL = `
  WITH route AS (
    -- The same route set gtfsRoutesSQL's bus branch emits, and for the same
    -- reason it has to be: a fare naming a route routes.txt dropped is a leg
    -- rule on a network no route belongs to, which is an invalid feed. Kept in
    -- step by TestGTFSFaresAreConsistent rather than by hope.
    SELECT DISTINCT ON (r.city, r.routeid) r.city, r.routeid, r.routeuid
    FROM raw_tdx.bus_route r
    WHERE COALESCE(TRIM(r.routeuid), '') <> ''
      AND jsonb_typeof(r.operators) = 'array'
      AND COALESCE(r.operators->0->>'OperatorID', '') <> ''
      AND COALESCE(TRIM(COALESCE(NULLIF(r.routename->>'Zh_tw', ''), r.routeid)), '') <> ''
    ORDER BY r.city, r.routeid, r.updatetime DESC NULLS LAST
  )
  SELECT route.routeuid, fu.stop_uid AS from_uid, tu.stop_uid AS to_uid, src.amount
  FROM ` + gtfsFareSrcTable + ` src
  JOIN route ON route.city = src.city AND route.routeid = src.routeid
  LEFT JOIN ` + gtfsStopUIDTable + ` fu ON fu.city = src.city AND fu.stop_id = src.from_id
  LEFT JOIN ` + gtfsStopUIDTable + ` tu ON tu.city = src.city AND tu.stop_id = src.to_id
  -- A pair whose stops do not resolve prices nothing, and keeping it would
  -- make the route look flat when it is not.
  WHERE (src.from_id IS NULL) = (fu.stop_uid IS NULL)
    AND (src.to_id IS NULL) = (tu.stop_uid IS NULL)`

var busFareLegSQL = `
  WITH flat AS (
    SELECT routeuid, MIN(amount) AS amount
    FROM ` + gtfsFarePairTable + `
    GROUP BY routeuid
    HAVING COUNT(DISTINCT amount) = 1
  )
  SELECT 'BUS:' || routeuid AS network_id, NULL::text AS from_uid, NULL::text AS to_uid, amount
  FROM flat
  UNION ALL
  SELECT 'BUS:' || p.routeuid, p.from_uid, p.to_uid, p.amount
  FROM ` + gtfsFarePairTable + ` p
  WHERE p.from_uid IS NOT NULL AND p.to_uid IS NOT NULL
    AND p.routeuid NOT IN (SELECT routeuid FROM flat)
  UNION ALL
  -- The mirrored half: a Fares v2 leg rule is directional and TDX prices one
  -- direction of most bus pairs, so without this a rider travelling the other
  -- way along the same route matches no rule and is quoted nothing. On the
  -- 2026-08-06 feed that was 89.7% of the 1,637,421 priced pairs.
  --
  -- Where TDX priced the reverse itself it is left alone — the source is the
  -- better authority on its own fare. Where it did not, the outbound price is
  -- assumed to hold: of the pairs priced both ways, 90% agree. The other 10% are
  -- the cost of this, and it is a deliberate trade of some wrong prices for a
  -- feed that can price a return journey at all.
  SELECT 'BUS:' || p.routeuid, p.to_uid, p.from_uid, p.amount
  FROM ` + gtfsFarePairTable + ` p
  WHERE p.from_uid IS NOT NULL AND p.to_uid IS NOT NULL
    AND p.routeuid NOT IN (SELECT routeuid FROM flat)
    AND NOT EXISTS (
      SELECT 1 FROM ` + gtfsFarePairTable + ` x
      WHERE x.routeuid = p.routeuid AND x.from_uid = p.to_uid AND x.to_uid = p.from_uid
    )`

// gtfsFareProductsSQL is one product per distinct amount, not per station pair.
//
// This is the difference between a fare model that fits in a feed and one that
// does not. The official MOTC feed emits a product per pair and its
// fare_products.txt is 2.8 GB with fare_leg_rules at 3.7 GB, together 88% of a
// 7.6 GB archive that no validator can open. A fare is a price, NT$20 is one
// price however many pairs charge it, and the leg rules do the pairing.
var gtfsFareProductsSQL = `
SELECT DISTINCT
  'P:' || amount::text AS fare_product_id,
  '' AS fare_product_name,
  -- TWD's minor unit is two digits, and GTFS wants an amount written to its
  -- currency's precision: 20 is rejected where 20.00 is read as NT$20. The id
  -- keeps the integer spelling — it is opaque, and fare_leg_rules names it.
  to_char(amount, 'FM999999990.00') AS amount,
  'TWD' AS currency
FROM (` + gtfsFareAllRulesSQL + `) p
ORDER BY fare_product_id`

// gtfsFareLegRulesSQL prices one leg: a journey on this network from this area
// to that area costs this product.
//
// network_id scopes the rule to one mode, which routes.txt carries. Without it a
// TRA fare would price a metro leg between two stations that happen to share an
// area, and Fares v2 has no other way to say "this rule is TRA's".
var gtfsFareLegRulesSQL = `
SELECT network_id, from_area_id, to_area_id, 'P:' || amount::text AS fare_product_id
FROM (` + gtfsFareAllRulesSQL + `) r
ORDER BY network_id, from_area_id, to_area_id`
