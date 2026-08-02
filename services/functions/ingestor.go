package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/robfig/cron/v3"
)

// rawFetcher is the context-aware, disk-spooled conditional-fetch surface used
// by the static ingestor. *shared.TDXClient is the production implementation;
// tests use a bounded fake to verify fan-out and error aggregation.
type rawFetcher interface {
	GetInto(context.Context, string, string, func(shared.TDXIntoCommit) error) (shared.TDXIntoResult, error)
}

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

// Metro system codes to land per endpoint. Each list is every system its
// endpoint accepts, so coverage is as wide as TDX allows; the lists differ only
// because TDX publishes a different system set per dataset, and answers an
// unsupported system with HTTP 400 rather than an empty payload.
//
// The lists are the endpoints' own answers, not a guess: TDX enumerates every
// accepted value in the 400 body, so one request with an invalid system returns
// the authoritative set. Re-probe that way when a system is added:
//
//	GET /v2/Rail/Metro/<Endpoint>/ZZZZ
var (
	// metroSystemsAll is every rail system TDX serves. Station, Shape, ODFare,
	// Route, StationOfRoute and Line all accept the full set.
	metroSystemsAll = []string{
		"TRTC", "KRTC", "TYMC", "KLRT", "NTDLRT", "NTALRT", "TMRT", "NTMC", "TRTCMG",
	}

	ingestMetroStationSystems = metroSystemsAll
	ingestMetroODFare         = metroSystemsAll
	// FirstLastTimetable omits the two newest light-rail lines.
	ingestMetroFirstLast = []string{"TRTC", "KRTC", "TYMC", "KLRT", "TMRT", "NTMC", "TRTCMG"}
	// S2STravelTime and LineTransfer feed the travel graph. Both consumers
	// (mrt_traveltime, mrt_adjacency) run over the S2STravelTime set; a system
	// with no LineTransfer partition reads as an empty array, which is the right
	// answer for a single-line system that has no line-to-line interchange.
	ingestMetroS2STravelTime = []string{"TRTC", "KRTC", "TYMC", "KLRT", "TMRT", "NTMC"}
	// LineTransfer is narrower than the four systems TDX accepts, because TYMC
	// serves an empty array and sends no Last-Modified header with it. The
	// landing path requires a marker (raw_land.go), so that partition fails every
	// run and never self-heals — it cannot record the state that would let a
	// later 304 pass. Airport MRT is single-line and genuinely has no interchange,
	// so there is nothing to lose by not asking. Restore TYMC here if it ever
	// gains a second line.
	ingestMetroLineTransfer = []string{"TRTC", "KRTC", "NTMC"}
	// The GTFS export endpoints. Their asymmetry is what the feed builder has to
	// work around: TMRT has routes and headways but no timetable, so Taichung is
	// expressible only as frequencies.txt; the three light-rail systems are the
	// reverse, with timetables but no headways; and TRTCMG (Maokong Gondola) has
	// routes, stations and exits but neither timetable nor headway, so it lands
	// with no service data at all and the builder must skip it (FDPL-6).
	ingestMetroFrequency = []string{"TRTC", "KRTC", "TYMC", "TMRT", "NTMC"}
	ingestMetroExit      = []string{"TRTC", "KRTC", "TYMC", "TMRT", "NTMC", "TRTCMG"}
	ingestMetroTimetable = []string{"TRTC", "KRTC", "TYMC", "KLRT", "NTDLRT", "NTALRT", "NTMC"}
)

const ingestTimeout = 20 * time.Minute

// busDailyIngestTimeout bounds one hourly bus_dailytimetable landing. It is a
// single dataset over ~23 city partitions, most of them answering 304, so it
// needs far less than the full run's budget.
const busDailyIngestTimeout = 10 * time.Minute

// registerIngestorCrons schedules the daily 03:00 raw landing (under a 20-minute
// timeout) plus the hourly bus_dailytimetable landing. When INGEST_ON_BOOT=true
// it also kicks off one full landing immediately in a goroutine, which is how a
// fresh deploy backfills raw_tdx without waiting for the next 03:00 tick. boot
// tracks that goroutine so drainShutdown waits for it instead of abandoning it
// mid-run on shutdown.
func registerIngestorCrons(r *cron.Cron, tdx *shared.TDXClient, rawPool *pgxpool.Pool, boot *sync.WaitGroup) {
	runner := newStaticPipelineRunner(rawPool, ingestTimeout)
	_, _ = addStaticCron(r, "0 0 3 * * *", func() {
		runDaily("ingest", ingestTimeout, func(ctx context.Context) error {
			return runner.Run(ctx, func(ctx context.Context) error {
				return ingestRaw(ctx, tdx)
			})
		})
	})
	// bus_dailytimetable is the one static feed TDX revises through the service
	// day, so it lands hourly on top of the 03:00 run instead of waiting a full
	// day. The conditional GET carries the cost: an unchanged city answers 304
	// and never touches raw_tdx. The static-pipeline lock inside runner.Run
	// serializes this against the 03:00 landing and the loader's runs, so the
	// 03:00 overlap needs no separate guard.
	hourly := newStaticPipelineRunner(rawPool, busDailyIngestTimeout)
	_, _ = addStaticCron(r, "0 0 * * * *", func() {
		runDaily("ingest_bus_dailytimetable", busDailyIngestTimeout, func(ctx context.Context) error {
			return hourly.Run(ctx, func(ctx context.Context) error {
				return ingestRaw(ctx, tdx, "bus_dailytimetable")
			})
		})
	})
	if os.Getenv("INGEST_ON_BOOT") == "true" {
		log.Infoln("[INGEST] INGEST_ON_BOOT=true — running once on boot")
		trackBoot(boot, func() {
			if err := runner.Run(context.Background(), func(ctx context.Context) error {
				return ingestRaw(ctx, tdx)
			}); err != nil {
				log.Errorf("[INGEST] action=boot event=failed error=%v", err)
			}
		})
	} else {
		log.Warn("[INGEST] INGEST_ON_BOOT not set — boot run skipped, daily cron only")
	}
}

// ingestRaw lands every configured TDX static endpoint into raw_tdx. Bus, bike,
// metro, and rail jobs share one three-request concurrency cap; rail timetable
// jobs cover the registry's date window. Each raw_tdx write happens inside
// fetchRaw's GetInto commit. Per-endpoint failures do not abort independent
// fetches, but all are joined and returned to the daily retry wrapper.
//
// tables, when non-empty, restricts the run to those raw_tdx tables — the
// hourly bus_dailytimetable landing is the one caller that lands a subset. An
// unknown table name lands nothing rather than silently falling back to the
// full run.
func ingestRaw(ctx context.Context, tdx rawFetcher, tables ...string) error {
	// Without TDX credentials every fetch would 401, so the ingestor would fire
	// ~300+ unauthenticated requests (each retried) daily to no effect. Gate the
	// whole run on non-empty credentials: the cron stays registered but is a true
	// no-op, emitting exactly one line and issuing zero requests. This is what
	// keeps staging/test (which run with empty creds against the shared Azure
	// database) from storming TDX and from racing prod's raw_tdx writes.
	if os.Getenv("TDX_CLIENT_ID") == "" || os.Getenv("TDX_CLIENT_SECRET") == "" {
		log.Infoln("[INGEST] action=raw event=idle reason=no_credentials")
		return nil
	}

	scope := "all"
	only := map[string]bool{}
	if len(tables) > 0 {
		scope = strings.Join(tables, ",")
		for _, t := range tables {
			only[t] = true
		}
	}
	log.Infof("[INGEST] action=raw event=start scope=%s", scope)
	landingCycle, err := newRawLandingCycle()
	if err != nil {
		return fmt.Errorf("start raw landing cycle: %w", err)
	}

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
		if len(only) > 0 && !only[d.rawTable] {
			continue
		}
		for _, part := range d.partitions() {
			jobs = append(jobs, job{d.url(part), d.name(part)})
		}
	}

	sem := make(chan struct{}, 3)
	var wg sync.WaitGroup
	failures := make(chan error, len(jobs))
	for _, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func(j job) {
			defer wg.Done()
			defer func() { <-sem }()
			if err := fetchRaw(ctx, tdx, j.url, j.name, landingCycle); err != nil {
				failures <- err
			}
		}(j)
	}
	wg.Wait()
	close(failures)
	joined := make([]error, 0, len(failures))
	for err := range failures {
		joined = append(joined, err)
	}
	log.Infof("[INGEST] action=raw event=end scope=%s", scope)
	return errors.Join(joined...)
}

// fetchRaw lands one static endpoint into raw_tdx via GetInto: the response is
// streamed to a seekable disk spool and dumped before the If-Modified-Since
// marker advances, so a failed dump refetches next run instead of being masked
// by a later 304. Endpoints with no raw_tdx mapping still advance their marker
// after the spool completes (commit is a no-op).
func fetchRaw(ctx context.Context, tdx rawFetcher, url, name, landingCycle string) error {
	return fetchRawWithVerifier(ctx, tdx, url, name, landingCycle, verifyAndTouchRawLanding)
}

type rawLandingVerifier func(context.Context, rawTarget, string, string) error

func fetchRawWithVerifier(
	ctx context.Context,
	tdx rawFetcher,
	url, name, landingCycle string,
	verify rawLandingVerifier,
) error {
	if landingCycle == "" {
		return errors.New("fetch raw: empty landing cycle")
	}
	target, mapped := rawDumpTarget(url)
	for attempt := range 2 {
		result, err := tdx.GetInto(ctx, url, name, func(commit shared.TDXIntoCommit) error {
			if !mapped {
				return nil
			}
			return dumpRawTDXReader(ctx, target, commit.Marker, landingCycle, commit.Body)
		})
		if err != nil {
			if errors.Is(err, errRawDump) {
				log.Errorf("[INGEST] url=%s event=raw_dump_error error=%v", url, err)
			} else {
				log.Errorf("[INGEST] url=%s event=fetch_error error=%v", url, err)
			}
			return fmt.Errorf("fetch raw %s: %w", url, err)
		}
		if result.Modified {
			return nil
		}
		if !mapped {
			log.Warnf("[INGEST] url=%s event=skip reason=not_modified", url)
			return nil
		}

		err = verify(ctx, target, result.Marker, landingCycle)
		if err == nil {
			log.Warnf("[INGEST] url=%s event=skip reason=not_modified", url)
			return nil
		}
		if !errors.Is(err, errRawLandingStateMismatch) {
			return fmt.Errorf("verify raw %s: %w", url, err)
		}
		if attempt == 1 {
			return fmt.Errorf("verify raw %s after forced refetch: %w", url, err)
		}
		if result.Invalidate == nil {
			return fmt.Errorf("verify raw %s: %w: nil marker invalidator", url, err)
		}
		if invalidateErr := result.Invalidate(); invalidateErr != nil {
			return fmt.Errorf("verify raw %s: %w", url, errors.Join(err, invalidateErr))
		}
		log.Infof("[INGEST] url=%s event=refetch reason=landing_state_mismatch", url)
	}
	return nil
}

func newRawLandingCycle() (string, error) {
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", fmt.Errorf("generate random identity: %w", err)
	}
	return hex.EncodeToString(random[:]), nil
}
