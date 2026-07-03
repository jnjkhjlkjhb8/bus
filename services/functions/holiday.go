package main

import (
	"encoding/csv"
	"io"
	"net/http"
	"strings"
	"time"
)

// holidayCSVURL is the New Taipei City open-data CSV of Taiwan national
// holidays / working-day adjustments, loaded at boot.
// Dataset: https://data.ntpc.gov.tw/datasets/308dcd75-6434-45bc-a95f-584da4fed251
const holidayCSVURL = "https://data.ntpc.gov.tw/api/datasets/308dcd75-6434-45bc-a95f-584da4fed251/csv/file"

// holidayMap maps "2006-01-02" to whether that date is a holiday. It stays nil
// until loadHolidays succeeds, and isHoliday falls back to weekends while nil.
var holidayMap map[string]bool

// taipei is the Asia/Taipei location used for all local-date calculations
// (holidays, hour/weekday features, schedule matching). Loaded in init.
var taipei *time.Location

// init loads the Asia/Taipei location and panics if the tz database is missing,
// since every date calculation in the package depends on it.
func init() {
	var err error
	taipei, err = time.LoadLocation("Asia/Taipei")
	if err != nil {
		panic("cannot load Asia/Taipei: " + err.Error())
	}
}

// loadHolidays fetches and parses the holiday CSV into holidayMap. On any fetch,
// status, or parse failure it logs and leaves holidayMap unchanged, so isHoliday
// keeps using the weekday fallback. The CSV's column 0 is the yyyymmdd date and
// column 3 holds "是" for a holiday.
func loadHolidays() {
	resp, err := http.Get(holidayCSVURL)
	if err != nil {
		log.Infof("[HOLIDAY] fetch error: %v — weekday fallback active", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		log.Infof("[HOLIDAY] fetch error: status=%d — weekday fallback active", resp.StatusCode)
		return
	}
	r := csv.NewReader(resp.Body)
	r.Read()
	m := make(map[string]bool)
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(rec) < 4 {
			continue
		}
		date := strings.TrimSpace(rec[0])
		if len(date) != 8 {
			continue
		}
		t, err := time.Parse("20060102", date)
		if err != nil {
			continue
		}
		m[t.Format("2006-01-02")] = strings.TrimSpace(rec[3]) == "是"
	}
	holidayMap = m
	log.Infof("[HOLIDAY] loaded %d entries", len(m))
}

// isHoliday reports whether t (evaluated in Taipei local time) is a holiday. It
// uses the loaded holiday table when available and otherwise falls back to
// treating Saturday and Sunday as holidays.
func isHoliday(t time.Time) bool {
	key := t.In(taipei).Format("2006-01-02")
	if holidayMap != nil {
		return holidayMap[key]
	}
	wd := t.In(taipei).Weekday()
	return wd == time.Saturday || wd == time.Sunday
}
