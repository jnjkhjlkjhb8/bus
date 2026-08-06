#!/usr/bin/env python3
"""Emit SQL comparing Data.taipei's 機動班表 headways with TDX's for Taipei.

FDPL-66 option C. Data.taipei publishes GetSemiTimeTable (per-weekday headway
windows); TDX publishes the same idea as Bus/Schedule Frequencys, already landed
in raw_tdx.bus_schedule. Neither is obviously better, so this measures both:
coverage, window counts, and the values themselves where they overlap.

Usage:

    python3 scripts/probe-datataipei-headway.py | psql "$DATABASE_URL"

Reads PG_SCHEMA only for symmetry with the other probe — every table it reads is
in raw_tdx, which is shared across environments.

Two shape mismatches the output has to be read against:

  * Data.taipei has no direction. TDX stores a headway per subroute *direction*,
    so one Data.taipei window faces one or two TDX rows.
  * Data.taipei's LongHeadway is the SMALLER value in 3,183 of 3,362 rows, so it
    is not "max headway" despite the name. The comparison below maps
    Low/Long onto max/min accordingly, and prints both so the mapping is
    checkable rather than assumed.
"""

import gzip
import json
import os
import sys
import urllib.request

BLOB = "https://tcgbusfs.blob.core.windows.net/blobbus/GetSemiTimeTable.gz"
SCHEMA = os.environ.get("PG_SCHEMA", "public")
CHUNK = 1000

# Data.taipei DateValue is 1=Sunday..7=Saturday; TDX ServiceDay is a named flag.
WEEKDAY = {
    "1": "Sunday", "2": "Monday", "3": "Tuesday", "4": "Wednesday",
    "5": "Thursday", "6": "Friday", "7": "Saturday",
}


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    with urllib.request.urlopen(BLOB, timeout=60) as resp:
        rows = json.loads(gzip.decompress(resp.read()))["BusInfo"]
    print(f"-- GetSemiTimeTable: {len(rows)} rows", file=sys.stderr)

    values = []
    for r in rows:
        # DateType 1 is a specific date rather than a weekday. One such row exists
        # and it names 2025-01-01, long past; it has no TDX counterpart to compare.
        day = WEEKDAY.get(r["DateValue"]) if r["DateType"] == "0" else None
        if day is None:
            continue
        values.append((
            str(r["PathAttributeId"]), day,
            r["StartTime"].replace(":", ""), r["EndTime"].replace(":", ""),
            r["LowHeadway"], r["LongHeadway"],
        ))

    print(f"SET search_path TO {SCHEMA};")
    print("CREATE TEMP TABLE dt_headway (path_id text, service_day text, "
          "start_time text, end_time text, low_headway text, long_headway text);")
    for start in range(0, len(values), CHUNK):
        chunk = ",\n".join(
            "(" + ", ".join(lit(v) for v in row) + ")" for row in values[start:start + CHUNK]
        )
        print(f"INSERT INTO dt_headway VALUES\n{chunk};")

    print("""
-- TDX's own headway windows for Taipei, one row per (subroute, direction,
-- window, service day) so the two sides compare on the same axis.
CREATE TEMP TABLE tdx_headway AS
SELECT s.subrouteuid,
       s.direction,
       d.key AS service_day,
       replace(f->>'StartTime', ':', '') AS start_time,
       replace(f->>'EndTime', ':', '')   AS end_time,
       (f->>'MinHeadwayMins')::int       AS min_headway,
       (f->>'MaxHeadwayMins')::int       AS max_headway
FROM raw_tdx.bus_schedule s,
     jsonb_array_elements(COALESCE(s.frequencys, '[]'::jsonb)) f,
     jsonb_each_text(f->'ServiceDay') d
WHERE s.city = 'Taipei' AND d.value = '1';
CREATE INDEX ON tdx_headway (subrouteuid, service_day, start_time);
ANALYZE tdx_headway;

\\echo === coverage: subroutes carrying any headway window
SELECT (SELECT count(DISTINCT 'TPE' || path_id) FROM dt_headway)   AS datataipei_subroutes,
       (SELECT count(DISTINCT subrouteuid) FROM tdx_headway)       AS tdx_subroutes,
       (SELECT count(*) FROM dt_headway)                           AS datataipei_windows,
       (SELECT count(*) FROM tdx_headway)                          AS tdx_windows;

\\echo === subroutes one side has and the other does not
SELECT count(*) FILTER (WHERE t.subrouteuid IS NULL) AS only_datataipei,
       count(*) FILTER (WHERE d.path_id IS NULL)     AS only_tdx
FROM (SELECT DISTINCT 'TPE' || path_id AS uid, path_id FROM dt_headway) d
FULL JOIN (SELECT DISTINCT subrouteuid FROM tdx_headway) t ON t.subrouteuid = d.uid;

\\echo === windows that line up exactly (same subroute, weekday, start and end)
SELECT count(*)                                                          AS matched_windows,
       count(*) FILTER (WHERE t.min_headway = d.long_headway::int)       AS min_equals_long,
       count(*) FILTER (WHERE t.max_headway = d.low_headway::int)        AS max_equals_low,
       count(*) FILTER (WHERE t.min_headway = d.low_headway::int)        AS min_equals_low,
       count(*) FILTER (WHERE t.max_headway = d.long_headway::int)       AS max_equals_long
FROM dt_headway d
JOIN tdx_headway t
  ON t.subrouteuid = 'TPE' || d.path_id
 AND t.service_day = d.service_day
 AND t.start_time = d.start_time
 AND t.end_time = d.end_time;

\\echo === 20 side-by-side samples on matched windows
SELECT t.subrouteuid, t.direction, d.service_day, d.start_time, d.end_time,
       t.min_headway, t.max_headway, d.long_headway, d.low_headway
FROM dt_headway d
JOIN tdx_headway t
  ON t.subrouteuid = 'TPE' || d.path_id
 AND t.service_day = d.service_day
 AND t.start_time = d.start_time
 AND t.end_time = d.end_time
ORDER BY t.subrouteuid, d.service_day, d.start_time
LIMIT 20;

\\echo === 20 Data.taipei windows TDX has no window for at all
SELECT DISTINCT 'TPE' || d.path_id AS subrouteuid, d.service_day, d.start_time, d.end_time,
       d.long_headway, d.low_headway
FROM dt_headway d
WHERE NOT EXISTS (
    SELECT 1 FROM tdx_headway t
    WHERE t.subrouteuid = 'TPE' || d.path_id AND t.service_day = d.service_day)
ORDER BY 1, 2, 3 LIMIT 20;
""")


if __name__ == "__main__":
    main()
