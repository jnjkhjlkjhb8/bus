package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/robfig/cron/v3"
)

// ROLE=ingestor fetches static TDX endpoints and lands the raw payloads into
// raw_tdx (via dumpRawTDX in fetchRaw's GetInto commit). No transforms, no
// per-env writes.

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
func registerIngestorCrons(r *cron.Cron, tdx *shared.TDXClient) {
	_, _ = r.AddFunc("0 0 3 * * *", func() {
		withTimeout(20*time.Minute, func(ctx context.Context) { ingestRaw(ctx, tdx) })
	})
	if os.Getenv("INGEST_ON_BOOT") == "true" {
		log.Infoln("[INGEST] INGEST_ON_BOOT=true — running once on boot")
		go ingestRaw(context.Background(), tdx)
	} else {
		log.Infoln("[INGEST] INGEST_ON_BOOT not set — boot run skipped, daily cron only")
	}
}

// ingestRaw lands every configured TDX static endpoint into raw_tdx: all bus
// APIs across all cities (run concurrently, capped at 3 in flight), then bike,
// metro, and rail endpoints sequentially. Rail daily timetables are fetched for
// today's date. Each fetch's raw_tdx write happens inside fetchRaw's GetInto
// commit; per-endpoint failures are logged and do not abort the run.
func ingestRaw(ctx context.Context, tdx *shared.TDXClient) {
	// Without TDX credentials every fetch would 401, so the ingestor would fire
	// ~300+ unauthenticated requests (each retried) daily to no effect. Gate the
	// whole run on non-empty credentials: the cron stays registered but is a true
	// no-op, emitting exactly one line and issuing zero requests. This is what
	// keeps staging/test (which run with empty creds against the shared Azure
	// database) from storming TDX and from racing prod's raw_tdx writes.
	if os.Getenv("TDX_CLIENT_ID") == "" || os.Getenv("TDX_CLIENT_SECRET") == "" {
		log.Infoln("[INGEST] action=raw event=idle reason=no_credentials")
		return
	}

	log.Infoln("[INGEST] action=raw event=start")

	type job struct{ url, name string }
	var jobs []job
	add := func(url, name string) { jobs = append(jobs, job{url, name}) }

	for _, city := range cities {
		for _, api := range ingestBusAPIs {
			if city == "InterCity" {
				add(fmt.Sprintf("/v2/Bus/%s/InterCity", api), "bus_"+api+city)
			} else {
				add(fmt.Sprintf("/v2/Bus/%s/City/%s", api, city), "bus_"+api+city)
			}
		}
	}

	for _, city := range cities {
		if !ingestBikeSkip[city] {
			add("/v2/Bike/Station/City/"+city, "bike_"+city)
		}
	}

	for _, s := range ingestMetroStationSystems {
		add("/v2/Rail/Metro/Station/"+s, "metro_station_"+s)
	}
	for _, s := range ingestMetroFirstLast {
		add("/v2/Rail/Metro/FirstLastTimetable/"+s, "metro_fl_"+s)
	}
	for _, s := range ingestMetroODFare {
		add("/v2/Rail/Metro/ODFare/"+s, "metro_od_"+s)
	}

	add("/v2/Rail/TRA/ODFare", "tra_odfare")
	// TRA/TrainType is intentionally not landed: nothing loads raw_tdx.tra_traintype,
	// and train-type data arrives inside the daily-timetable payloads below.
	add("/v2/Rail/TRA/Station", "tra_station")
	add("/v2/Rail/THSR/Station", "thsr_station")
	add("/v2/Rail/THSR/ODFare", "thsr_odfare")

	// Land the full timetable window (TRA today..+60, THSR today..+45),
	// mirroring railPreFetch's horizons. Day 0 is today so the current day is
	// landed; the per-date IMS cache key isolates each date's If-Modified-Since
	// state, and rawDumpTarget partitions each date by its traindate column so a
	// mid-run refresh replaces only that date rather than TRUNCATE'ing the table.
	today := time.Now()
	for i := 0; i <= 60; i++ {
		d := today.AddDate(0, 0, i).Format(time.DateOnly)
		add("/v2/Rail/TRA/DailyTimetable/TrainDate/"+d, "tra_daily_"+d)
	}
	for i := 0; i <= 45; i++ {
		d := today.AddDate(0, 0, i).Format(time.DateOnly)
		add("/v2/Rail/THSR/DailyTimetable/TrainDate/"+d, "thsr_daily_"+d)
	}
	sem := make(chan struct{}, 3)
	var wg sync.WaitGroup
	for _, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func(j job) {
			defer wg.Done()
			defer func() { <-sem }()
			fetchRaw(ctx, tdx, j.url, j.name)
		}(j)
	}
	wg.Wait()
	log.Infoln("[INGEST] action=raw event=end")
}

// fetchRaw lands one static endpoint into raw_tdx via GetInto: the whole body is
// buffered and dumped before the If-Modified-Since marker advances, so a failed
// dump refetches next run instead of being masked by a later 304. The ingestor
// never parses the payload — only the raw bytes matter. Endpoints with no
// raw_tdx mapping still advance their marker (commit is a no-op).
func fetchRaw(ctx context.Context, tdx *shared.TDXClient, url, name string) {
	modified, err := tdx.GetInto(url, name, func(body []byte) error {
		table, partCol, partVal, ok := rawDumpTarget(url)
		if !ok {
			return nil
		}
		return dumpRawTDX(ctx, table, partCol, partVal, body)
	})
	if err != nil {
		if errors.Is(err, errRawDump) {
			log.Infof("[INGEST] url=%s event=raw_dump_error error=%v", url, err)
		} else {
			log.Infof("[INGEST] url=%s event=fetch_error error=%v", url, err)
		}
		return
	}
	if !modified {
		log.Infof("[INGEST] url=%s event=skip reason=not_modified", url)
	}
}
