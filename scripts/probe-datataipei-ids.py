#!/usr/bin/env python3
"""Emit SQL that measures how well Data.taipei bus IDs map onto TDX UIDs.

FDPL-66 Phase 0 gate. Data.taipei (大臺北公車) keys everything on bare numbers;
this repo keys on TDX UIDs ("TPE" or "NWT" + the same number, is the guess).
If that guess does not hold, none of the later phases can join the two sources.

Usage (the DB is only reachable from the maintainer's machine):

    python3 scripts/probe-datataipei-ids.py | psql "$DATABASE_URL"

Reads PG_SCHEMA (default "public") so it can be pointed at staging.

The name columns are the point of the check, not decoration: a bare number can
collide across cities, so a UID that resolves to a differently named route is a
false hit, not a hit.
"""

import gzip
import json
import os
import sys
import urllib.request

BLOB = "https://tcgbusfs.blob.core.windows.net/blobbus/"
SCHEMA = os.environ.get("PG_SCHEMA", "public")
CHUNK = 1000


def fetch(name):
    with urllib.request.urlopen(BLOB + name + ".gz", timeout=60) as resp:
        return json.loads(gzip.decompress(resp.read()))["BusInfo"]


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def emit(table, columns, rows):
    print(f"CREATE TEMP TABLE {table} ({', '.join(c + ' text' for c in columns)});")
    for start in range(0, len(rows), CHUNK):
        values = ",\n".join(
            "(" + ", ".join(lit(v) for v in row) + ")" for row in rows[start:start + CHUNK]
        )
        print(f"INSERT INTO {table} VALUES\n{values};")


def main():
    routes = fetch("GetRoute")
    stops = fetch("GetStop")
    print(f"-- GetRoute: {len(routes)} rows, GetStop: {len(stops)} rows", file=sys.stderr)

    print(f"SET search_path TO {SCHEMA};")
    emit("dt_route", ["id", "path_id", "name"],
         [(r["Id"], r["pathAttributeId"], r["nameZh"]) for r in routes])
    # One row per stop id: the feed repeats a stop across directions, and the
    # name is identical each time, so the first occurrence is representative.
    seen = {}
    for s in stops:
        seen.setdefault(str(s["Id"]), s["nameZh"])
    emit("dt_stop", ["id", "name"], sorted(seen.items()))

    print("""
-- GetRoute repeats a main route once per 附屬路線, so route-level counts run over
-- the distinct Ids; the subroute check below keeps every row.
CREATE TEMP VIEW dt_main AS SELECT DISTINCT id, name FROM dt_route;

\\echo === routes: Data.taipei Id -> bus_static.route_uid
SELECT count(*) AS total,
       count(*) FILTER (WHERE m.route_uid IS NOT NULL) AS matched,
       count(*) FILTER (WHERE m.route_uid LIKE 'TPE%') AS as_tpe,
       count(*) FILTER (WHERE m.route_uid LIKE 'NWT%') AS as_nwt,
       count(*) FILTER (WHERE m.route_uid IS NOT NULL AND m.route_name <> d.name) AS name_mismatch
FROM dt_main d
LEFT JOIN LATERAL (
    SELECT s.route_uid, s.route_name FROM bus_static s
    WHERE s.route_uid IN ('TPE' || d.id, 'NWT' || d.id) LIMIT 1
) m ON true;

\\echo === subroutes: Data.taipei pathAttributeId -> bus_static.sub_route_uid
SELECT count(*) AS total,
       count(*) FILTER (WHERE m.sub_route_uid IS NOT NULL) AS matched,
       count(*) FILTER (WHERE m.sub_route_uid LIKE 'TPE%') AS as_tpe,
       count(*) FILTER (WHERE m.sub_route_uid LIKE 'NWT%') AS as_nwt
FROM dt_route d
LEFT JOIN LATERAL (
    SELECT s.sub_route_uid FROM bus_static s
    WHERE s.sub_route_uid IN ('TPE' || d.path_id, 'NWT' || d.path_id) LIMIT 1
) m ON true;

-- bus_station_stop_map's primary key leads with sub_route_uid, so a stop_uid
-- lookup scans the table. Collapse it to one row per stop up front (one scan)
-- and index that, or the 28k probes below run a scan each.
CREATE TEMP TABLE tdx_stop AS
SELECT DISTINCT ON (stop_uid) stop_uid, station_name
FROM bus_station_stop_map
WHERE stop_uid LIKE 'TPE%' OR stop_uid LIKE 'NWT%'
ORDER BY stop_uid;
CREATE INDEX ON tdx_stop (stop_uid);
ANALYZE tdx_stop;

\\echo === stops: Data.taipei Id -> bus_station_stop_map.stop_uid
SELECT count(*) AS total,
       count(*) FILTER (WHERE m.stop_uid IS NOT NULL) AS matched,
       count(*) FILTER (WHERE m.stop_uid LIKE 'TPE%') AS as_tpe,
       count(*) FILTER (WHERE m.stop_uid LIKE 'NWT%') AS as_nwt,
       count(*) FILTER (WHERE m.stop_uid IS NOT NULL AND m.station_name <> d.name) AS name_mismatch
FROM dt_stop d
LEFT JOIN LATERAL (
    SELECT p.stop_uid, p.station_name FROM tdx_stop p
    WHERE p.stop_uid IN ('TPE' || d.id, 'NWT' || d.id) LIMIT 1
) m ON true;

\\echo === 20 unmatched routes (sample)
SELECT d.id, d.name FROM dt_main d
WHERE NOT EXISTS (SELECT 1 FROM bus_static s
                  WHERE s.route_uid IN ('TPE' || d.id, 'NWT' || d.id))
ORDER BY d.id LIMIT 20;

\\echo === 20 name mismatches on matched stops (sample)
SELECT d.id, d.name AS datataipei_name, m.station_name AS tdx_name
FROM dt_stop d
JOIN LATERAL (
    SELECT p.stop_uid, p.station_name FROM tdx_stop p
    WHERE p.stop_uid IN ('TPE' || d.id, 'NWT' || d.id) LIMIT 1
) m ON true
WHERE m.station_name <> d.name
ORDER BY d.id LIMIT 20;
""")


if __name__ == "__main__":
    main()
