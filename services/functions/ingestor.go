package main

import (
	"context"
	"errors"
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

// cities with no public bike-share feed.
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
	ingestMetroODFare         = []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	ingestMetroTravelGraph    = []string{"TRTC"}
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

	// Build the fetch jobs from the single datasetRegistry: every fetched dataset
	// (familyNone / landOnly excluded) crossed with its landing partitions. The
	// timetable datasets land the full window (TRA today..+60, THSR today..+45);
	// day 0 is today, the per-date IMS cache key isolates each date's
	// If-Modified-Since state, and rawDumpTarget partitions each date by its
	// traindate column so a mid-run refresh replaces only that date.
	type job struct{ url, name string }
	var jobs []job
	for _, d := range datasetRegistry() {
		if !d.fetched() {
			continue
		}
		for _, part := range d.partitions() {
			jobs = append(jobs, job{d.url(part), d.name(part)})
		}
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
		// 304: nothing landed, but the landed partition is verified current — bump
		// fetched_at so the loader's staleness window doesn't skip it forever.
		if table, partCol, partVal, ok := rawDumpTarget(url); ok {
			if err := touchRawTDX(ctx, table, partCol, partVal); err != nil {
				log.Infof("[INGEST] url=%s event=touch_error error=%v", url, err)
				return
			}
		}
		log.Infof("[INGEST] url=%s event=skip reason=not_modified", url)
	}
}
