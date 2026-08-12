package main

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"go.uber.org/zap"
)

// Taipei's daily timetable, landed from Data.taipei instead of TDX (FDPL-66
// Phase 3). TDX answers HTTP 400 for Bus/DailyTimeTable/City/Taipei, so the city
// has never had one; GetSpecTimeTable (特殊班表 — the operators' own filed
// schedules for the next few days) is the one Data.taipei feed that carries
// everything the loader needs: a subroute, a direction, dated trips, and a
// departure time.
//
// Deliberately not landed here:
//
//   - GetTimeTable (常態班表) has no direction field at all, and GetRoute cannot
//     supply one — its go/back first/last bus times are identical on every route
//     sampled. Filing 35k departures under a guessed direction would fill 去程 and
//     leave 回程 empty, which is wrong data rather than thin data.
//   - GetSemiTimeTable (機動班表) is headway windows (StartTime/EndTime plus a
//     high/low 發車間距), not trips. It has no stop, no departure time and no
//     direction, so bus_dailytimetable — a table of trips with stop times — has
//     nowhere to put it. TDX's Bus/Schedule frequencys column is that shape's
//     home, and it already lands for Taipei.
//
// What does land is small and short-dated: 38 subroutes, 去程 only, three days
// rolling. It is additive — Taipei previously had none — so a thin feed is worth
// landing, but it is not a Taipei-wide timetable and should not be read as one.

// dataTaipeiSpecTimeTable is the GetSpecTimeTable envelope. Every list in it is
// wrapped in a singular-named object (timeTables.timeTable), an XML shape
// carried over into the JSON.
type dataTaipeiSpecTimeTable struct {
	SpecificTimeTables struct {
		SpecificTimeTable []dataTaipeiSpecEntry `json:"specificTimeTable"`
	} `json:"specificTimeTables"`
}

// dataTaipeiSpecEntry is one subroute direction's filed schedule.
type dataTaipeiSpecEntry struct {
	SubRouteID string `json:"subRouteID"`
	Direction  string `json:"direction"`
	TimeTables struct {
		TimeTable []dataTaipeiSpecTrip `json:"timeTable"`
	} `json:"timeTables"`
}

// dataTaipeiSpecTrip is one departure, with the dates it is filed for.
type dataTaipeiSpecTrip struct {
	StopTimes struct {
		StopTime []dataTaipeiSpecStopTime `json:"stopTime"`
	} `json:"stopTimes"`
	SpecialDays struct {
		SpecialDay []dataTaipeiSpecialDay `json:"specialDay"`
	} `json:"specialDays"`
}

type dataTaipeiSpecStopTime struct {
	StopSequence  int64  `json:"stopSequence"`
	StopID        string `json:"stopID"`
	ArrivalTime   string `json:"arrivalTime"`
	DepartureTime string `json:"departureTime"`
}

type dataTaipeiSpecialDay struct {
	Dates struct {
		Date []string `json:"date"`
	} `json:"dates"`
	ServiceStatus string `json:"serviceStatus"`
}

// busDailyKey groups the reshaped trips by the subroute direction they belong to.
type busDailyKey struct {
	subRouteUID string
	direction   uint8
}

// _dataTaipeiServiceRunning is the serviceStatus for 正常營運. 0 is 停止營運 and 2
// is 加班營運; only a running trip belongs in a timetable of departures.
const _dataTaipeiServiceRunning = "1"

// busDailyTimetableRow mirrors the TDX Bus/DailyTimeTable element the landing
// path lowercases into raw_tdx.bus_dailytimetable and loadBusDailyTimetable
// decodes back out. The field names are TDX's, not Data.taipei's, because that
// is the contract raw_tdx stores.
type busDailyTimetableRow struct {
	SubRouteUID string                  `json:"SubRouteUID"`
	Direction   uint8                   `json:"Direction"`
	BusDate     string                  `json:"BusDate"`
	Timetables  []busDailyTimetableTrip `json:"Timetables"`
}

type busDailyTimetableTrip struct {
	TripID     string                      `json:"TripID"`
	IsLowFloor bool                        `json:"IsLowFloor"`
	StopTimes  []busDailyTimetableStopTime `json:"StopTimes"`
}

type busDailyTimetableStopTime struct {
	StopSequence  int64  `json:"StopSequence"`
	StopUID       string `json:"StopUID"`
	ArrivalTime   string `json:"ArrivalTime"`
	DepartureTime string `json:"DepartureTime"`
}

// dataTaipeiDailyTimetableRows selects the trips running on day and reshapes
// them into TDX's daily-timetable element, one per subroute direction.
//
// Trips are dropped rather than repaired when they cannot be filed: a direction
// the feed leaves as "null" (17 of 94 entries on 2026-08-06) names no travel
// direction, and a stop time that fails validClock would fail the loader's own
// validation and take the whole city's landing with it.
//
// TripID is synthesised from the date and the origin departure because
// GetSpecTimeTable has none. The loader uses it as a dedupe key within one
// subroute direction, and (date, departure) is unique there by construction.
func dataTaipeiDailyTimetableRows(feed dataTaipeiSpecTimeTable, day time.Time) []busDailyTimetableRow {
	date := day.Format("2006-01-02")
	byKey := make(map[busDailyKey]*busDailyTimetableRow)
	var order []busDailyKey
	for _, entry := range feed.SpecificTimeTables.SpecificTimeTable {
		direction, ok := dataTaipeiDirection(entry.Direction)
		if !ok || strings.TrimSpace(entry.SubRouteID) == "" {
			continue
		}
		uid := _dataTaipeiUIDPrefix + entry.SubRouteID
		for _, trip := range entry.TimeTables.TimeTable {
			if !dataTaipeiRunsOn(trip.SpecialDays.SpecialDay, date) {
				continue
			}
			stopTimes := make([]busDailyTimetableStopTime, 0, len(trip.StopTimes.StopTime))
			for _, st := range trip.StopTimes.StopTime {
				if st.StopSequence <= 0 || strings.TrimSpace(st.StopID) == "" {
					continue
				}
				if !validClock(st.ArrivalTime) || !validClock(st.DepartureTime) {
					continue
				}
				stopTimes = append(stopTimes, busDailyTimetableStopTime{
					StopSequence:  st.StopSequence,
					StopUID:       _dataTaipeiUIDPrefix + st.StopID,
					ArrivalTime:   st.ArrivalTime,
					DepartureTime: st.DepartureTime,
				})
			}
			if len(stopTimes) == 0 {
				continue
			}
			key := busDailyKey{subRouteUID: uid, direction: direction}
			row, seen := byKey[key]
			if !seen {
				row = &busDailyTimetableRow{SubRouteUID: uid, Direction: direction, BusDate: date}
				byKey[key] = row
				order = append(order, key)
			}
			row.Timetables = append(row.Timetables, busDailyTimetableTrip{
				TripID:    date + "-" + strings.ReplaceAll(stopTimes[0].DepartureTime, ":", ""),
				StopTimes: stopTimes,
			})
		}
	}
	rows := make([]busDailyTimetableRow, 0, len(order))
	for _, key := range order {
		row := byKey[key]
		// Stable output so an unchanged feed lands identical bytes: the map
		// iteration above fixes the row order, this fixes the trips within a row.
		sort.Slice(row.Timetables, func(i, j int) bool {
			return row.Timetables[i].TripID < row.Timetables[j].TripID
		})
		rows = append(rows, *row)
	}
	return rows
}

// dataTaipeiRunsOn reports whether any of a trip's special-day entries puts it
// in normal service on date.
func dataTaipeiRunsOn(days []dataTaipeiSpecialDay, date string) bool {
	for _, d := range days {
		if d.ServiceStatus != _dataTaipeiServiceRunning {
			continue
		}
		for _, on := range d.Dates.Date {
			if on == date {
				return true
			}
		}
	}
	return false
}

// landDataTaipeiDailyTimetable fetches 特殊班表 and lands today's trips as
// Taipei's raw_tdx.bus_dailytimetable partition. An unchanged blob still lands:
// the partition is dated, so yesterday's rows have to be replaced when the day
// rolls over even though the feed did not move.
func landDataTaipeiDailyTimetable(ctx context.Context, f *dataTaipeiFeed, now func() time.Time) error {
	var feed dataTaipeiSpecTimeTable
	if _, err := f.getEnvelope(ctx, "GetSpecTimeTable", &feed); err != nil {
		return _oops.Wrapf(err, "fetch Data.taipei spec timetable")
	}
	day := now().In(_taipei)
	rows := dataTaipeiDailyTimetableRows(feed, day)
	body, err := json.Marshal(rows)
	if err != nil {
		return _oops.Wrapf(err, "encode Data.taipei daily timetable")
	}
	cycle, err := newRawLandingCycle()
	if err != nil {
		return err
	}
	// The marker records which service date these rows describe. The blob's own
	// ETag would go stale in the wrong direction: it stays put across midnight
	// while the rows it produces change.
	marker := "datataipei:" + day.Format("2006-01-02")
	target := rawTarget{table: "bus_dailytimetable", partCol: "city", partVal: _dataTaipeiCity}
	if err := dumpRawTDX(ctx, target, marker, cycle, body); err != nil {
		return err
	}
	zap.S().Infow("landed",
		"component", "ingest",
		"action", "datataipei_dailytimetable",
		"event", "landed",
		"city", _dataTaipeiCity,
		"date", marker,
		"subroute_directions", len(rows),
	)
	return nil
}
