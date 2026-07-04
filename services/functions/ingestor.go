package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/robfig/cron/v3"
)

// ROLE=ingestor fetches static TDX endpoints and lands the raw payloads into
// raw_tdx (via dumpRawTDX inside callApi). No transforms, no per-env writes.

// ingestBusAPIs lists the TDX Bus static endpoints landed for every city in one
// ingestor run.
var ingestBusAPIs = []string{
	"Route", "StopOfRoute", "Shape", "Schedule", "Station", "StationGroup",
	"Operator", "RouteFare", "DailyTimeTable",
}

// mirrors getbikeStation's skip list — cities with no public bike-share feed.
var ingestBikeSkip = map[string]bool{
	"Keelung": true, "HsinchuCounty": true, "NantouCounty": true,
	"YilanCounty": true, "PenghuCounty": true, "KinmenCounty": true,
	"LienchiangCounty": true, "InterCity": true, "HualienCounty": true,
}

// Metro system codes to land per endpoint. The lists differ because not every
// system publishes every dataset (e.g. NTMC has stations but no first/last
// timetable or OD fare feed).
var (
	ingestMetroStationSystems = []string{"TRTC", "KRTC", "KLRT", "TYMC", "NTMC"}
	ingestMetroFirstLast      = []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	ingestMetroODFare         = []string{"TRTC", "KRTC", "KLRT"}
)

// registerIngestorCrons schedules the daily 03:00 raw landing (under a 20-minute
// timeout). When INGEST_ON_BOOT=true it also kicks off one landing immediately in
// a goroutine, which is how a fresh deploy backfills raw_tdx without waiting for
// the next 03:00 tick.
func registerIngestorCrons(r *cron.Cron, c *resty.Client, rc *redis.Client) {
	_, _ = r.AddFunc("0 0 3 * * *", func() {
		withTimeout(20*time.Minute, func(ctx context.Context) { ingestRaw(ctx, c, rc) })
	})
	if os.Getenv("INGEST_ON_BOOT") == "true" {
		log.Infoln("[INGEST] INGEST_ON_BOOT=true — running once on boot")
		go ingestRaw(context.Background(), c, rc)
	} else {
		log.Infoln("[INGEST] INGEST_ON_BOOT not set — boot run skipped, daily cron only")
	}
}

// ingestRaw lands every configured TDX static endpoint into raw_tdx: all bus
// APIs across all cities (run concurrently, capped at 4 in flight), then bike,
// metro, and rail endpoints sequentially. Rail daily timetables are fetched for
// today's date. Each fetch's raw_tdx write happens inside callApi; per-endpoint
// failures are logged and do not abort the run.
func ingestRaw(ctx context.Context, c *resty.Client, rc *redis.Client) {
	log.Infoln("[INGEST] action=raw event=start")

	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	for _, city := range cities {
		for _, api := range ingestBusAPIs {
			var url string
			if city == "InterCity" {
				url = fmt.Sprintf("/v2/Bus/%s/InterCity", api)
			} else {
				url = fmt.Sprintf("/v2/Bus/%s/City/%s", api, city)
			}
			name := "bus_" + api + city
			wg.Add(1)
			sem <- struct{}{}
			go func(url, name string) {
				defer wg.Done()
				defer func() { <-sem }()
				fetchRaw(c, rc, url, name)
			}(url, name)
		}
	}
	wg.Wait()

	for _, city := range cities {
		if ingestBikeSkip[city] {
			continue
		}
		fetchRaw(c, rc, "/v2/Bike/Station/City/"+city, "bike_"+city)
	}

	for _, s := range ingestMetroStationSystems {
		fetchRaw(c, rc, "/v2/Rail/Metro/Station/"+s, "metro_station_"+s)
	}
	for _, s := range ingestMetroFirstLast {
		fetchRaw(c, rc, "/v2/Rail/Metro/FirstLastTimetable/"+s, "metro_fl_"+s)
	}
	for _, s := range ingestMetroODFare {
		fetchRaw(c, rc, "/v2/Rail/Metro/ODFare/"+s, "metro_od_"+s)
	}

	fetchRaw(c, rc, "/v2/Rail/TRA/ODFare", "tra_odfare")
	fetchRaw(c, rc, "/v2/Rail/TRA/TrainType", "tra_traintype")
	fetchRaw(c, rc, "/v2/Rail/TRA/Station", "tra_station")
	fetchRaw(c, rc, "/v2/Rail/THSR/Station", "thsr_station")
	fetchRaw(c, rc, "/v2/Rail/THSR/ODFare", "thsr_odfare")

	// Land the full timetable window (TRA today..+60, THSR today..+45),
	// mirroring railPreFetch's horizons. Day 0 is today so the current day is
	// landed; the per-date IMS cache key isolates each date's If-Modified-Since
	// state, and rawDumpTarget partitions each date by its traindate column so a
	// mid-run refresh replaces only that date rather than TRUNCATE'ing the table.
	today := time.Now()
	for i := 0; i <= 60; i++ {
		d := today.AddDate(0, 0, i).Format(time.DateOnly)
		fetchRaw(c, rc, "/v2/Rail/TRA/DailyTimetable/TrainDate/"+d, "tra_daily_"+d)
	}
	for i := 0; i <= 45; i++ {
		d := today.AddDate(0, 0, i).Format(time.DateOnly)
		fetchRaw(c, rc, "/v2/Rail/THSR/DailyTimetable/TrainDate/"+d, "thsr_daily_"+d)
	}

	log.Infoln("[INGEST] action=raw event=end")
}

// fetchRaw calls a static endpoint; the raw_tdx landing happens inside callApi.
// The returned decoder is intentionally discarded — the ingestor never parses.
func fetchRaw(c *resty.Client, rc *redis.Client, url, name string) {
	_, comp, err, done := callApi(c, rc, url, name)
	if done != nil {
		defer done()
	}
	if err != nil {
		if errors.Is(err, errRawDump) {
			log.Infof("[INGEST] url=%s event=raw_dump_error error=%v", url, err)
		} else {
			log.Infof("[INGEST] url=%s event=fetch_error error=%v", url, err)
		}
		return
	}
	if !comp {
		log.Infof("[INGEST] url=%s event=skip reason=not_modified", url)
	}
}
