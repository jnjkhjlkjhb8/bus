//go:build shadow

package maas

// The TDX/MOTIS shadow comparison (ADR-0022).
//
// This is the cutover's acceptance gate, and it is only runnable while TDX is
// still serving -- which is why it is a precondition of the switch rather than
// follow-up work.
//
// It lives as a build-tagged test in this package, rather than as a script,
// because it calls the production request mapping directly: motisPlanQuery,
// motisClient.Plan and MaasServer.fetch are the same functions the router uses.
// A standalone script would have to reimplement the mode translation, the time
// format and the first/last-mile mapping, and would then be measuring its own
// copy -- drifting in exactly the direction that reports green while production
// is broken.
//
// The tag keeps it out of `go test ./...` entirely: nothing here compiles
// unless it is asked for.
//
//	DATABASE_URL=... TDX_CLIENT_ID=... TDX_CLIENT_SECRET=... \
//	MOTIS_BASE_URL=http://127.0.0.1:8082 \
//	go test -tags=shadow ./services/api -run TestShadowCompare -v -timeout 60m
//
// The gate is the no-result rate, not the travel-time delta. TDX prices live
// traffic and MOTIS prices a timetable, so their times differ without either
// being wrong; "MOTIS returns nothing where TDX returned something" is the
// binary, un-arguable failure, and it is what the feed's known holes (Taichung,
// the four cities whose bus times are accumulated rather than observed) would
// produce.

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
)

const (
	// _shadowSeed fixes the corpus. A configuration change has to be measurable
	// against the same origin/destination pairs as the run before it, or the
	// difference between two runs is the sample rather than the change.
	_shadowSeed = 20260817
	// _shadowPairs is how many origin/destination pairs are drawn. Large enough
	// that a 2 percentage point threshold is not one unlucky pair, small enough
	// to stay inside TDX's quota.
	_shadowPairs = 400
	// _shadowThresholdPP is the gate from ADR-0022: MOTIS's no-result rate may
	// exceed TDX's by at most this many percentage points.
	_shadowThresholdPP = 2.0
	// _shadowMinRegionShare is the floor for Taichung and for the south, each
	// as a share of the corpus. Without it the sample is Taipei, which is where
	// the feed is strongest -- a green run would then mean nothing about the
	// places most likely to fail.
	_shadowMinRegionShare = 0.15
	// _shadowRequestGap paces the run. TDX is a metered third party and MOTIS
	// shares a 6 GB host with everything else; there is no deadline here worth
	// degrading either for.
	_shadowRequestGap = 250 * time.Millisecond
)

// shadowRegionOf partitions Taiwan by the `city` column the stop tables carry.
// The split is by where the feed's quality actually differs, not by geography
// for its own sake: Taipei and New Taipei are where bus times are accumulated
// from segment estimates, Taichung is the hole both our feed and the official
// one miss, and the south is where coverage is thinnest.
//
// The table is built per call rather than held in a package-level map, which
// would be a mutable global any test in this package could reach into.
func shadowRegionOf(city string) string {
	regions := map[string][]string{
		"north":    {"Taipei", "NewTaipei", "Keelung", "Taoyuan", "Hsinchu", "HsinchuCounty"},
		"taichung": {"Taichung"},
		"south":    {"Tainan", "Kaohsiung", "Chiayi", "ChiayiCounty", "Pingtung", "Yunlin"},
	}
	for region, cities := range regions {
		for _, candidate := range cities {
			if strings.EqualFold(candidate, city) {
				return region
			}
		}
	}
	return "elsewhere"
}

type shadowPlace struct {
	name   string
	city   string
	region string
	lat    float64
	lon    float64
}

type shadowOutcome struct {
	routes     int
	travelTime int64
	transfers  int32
	err        error
}

func (o shadowOutcome) empty() bool { return o.err != nil || o.routes == 0 }

func TestShadowCompare(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL unset; the corpus is drawn from the stop tables")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	db := shared.ConnectDB("ROUTER_DB_MAX_CONNS", 4)
	defer db.Close()

	places, err := shadowPlaces(ctx, db)
	if err != nil {
		t.Fatalf("draw corpus: %v", err)
	}
	pairs := shadowPairs(places)
	reportShadowComposition(t, pairs)

	motis := NewMotisClient(MotisBaseURLFromEnv())
	tdxClient := shared.NewTDXClient(shared.TDXConfig{
		// An in-process token store rather than the Redis one main uses: this
		// run is a single process with a single token, and reaching for Redis
		// would make an acceptance tool depend on a service it is not testing.
		Store:  &shadowTokenStore{values: map[string]string{}},
		IMSKey: shared.TDXLegacyIMSKey,
	})
	tdx := NewMaasServerWithCache(newShadowCache(), nil, tdxClient, DefaultMaasSharedWorkConfig)
	defer tdx.Close()

	var motisEmpty, tdxEmpty, bothAnswered int
	byRegion := map[string]*[2]int{}
	for i, pair := range pairs {
		req := shadowRequest(pair)

		motisResult := runShadowMotis(ctx, motis, req)
		time.Sleep(_shadowRequestGap)
		tdxResult := runShadowTDX(ctx, tdx, req)
		time.Sleep(_shadowRequestGap)

		counts, ok := byRegion[pair.from.region]
		if !ok {
			counts = &[2]int{}
			byRegion[pair.from.region] = counts
		}
		if motisResult.empty() {
			motisEmpty++
			counts[0]++
		}
		if tdxResult.empty() {
			tdxEmpty++
			counts[1]++
		}
		if !motisResult.empty() && !tdxResult.empty() {
			bothAnswered++
		}
		t.Logf("%3d/%d %s %s -> %s | motis %s | tdx %s",
			i+1, len(pairs), pair.from.region, pair.from.name, pair.to.name,
			describeShadow(motisResult), describeShadow(tdxResult))
	}

	total := float64(len(pairs))
	motisRate := 100 * float64(motisEmpty) / total
	tdxRate := 100 * float64(tdxEmpty) / total
	t.Logf("")
	t.Logf("pairs=%d both answered=%d", len(pairs), bothAnswered)
	t.Logf("no-result rate: motis %.1f%% (%d) tdx %.1f%% (%d) delta %+.1fpp",
		motisRate, motisEmpty, tdxRate, tdxEmpty, motisRate-tdxRate)
	for _, region := range sortedKeys(byRegion) {
		counts := byRegion[region]
		t.Logf("  %-10s motis %d tdx %d", region, counts[0], counts[1])
	}

	// The gate. A MOTIS that answers *more* often than TDX passes trivially,
	// which is correct: the threshold is one-sided on purpose.
	if delta := motisRate - tdxRate; delta > _shadowThresholdPP {
		t.Fatalf("no-result rate exceeds TDX by %.1fpp, threshold is %.1fpp", delta, _shadowThresholdPP)
	}
}

// shadowRequest is a plain weekday-morning departure. The options are left at
// their defaults deliberately: this measures whether a plan exists at all, and
// a narrowed mode filter or a tightened transfer window would confound that
// with the filter's own effect.
func shadowRequest(pair shadowPair) *pb.MaasPlanRequest {
	departure := time.Now().Add(24 * time.Hour)
	for departure.Weekday() == time.Saturday || departure.Weekday() == time.Sunday {
		departure = departure.Add(24 * time.Hour)
	}
	return &pb.MaasPlanRequest{
		FromLat: pair.from.lat, FromLon: pair.from.lon,
		ToLat: pair.to.lat, ToLon: pair.to.lon,
		Date: departure.Format("2006-01-02"),
		Time: "09:00",
		Top:  5,
	}
}

func runShadowMotis(ctx context.Context, client *motisClient, req *pb.MaasPlanRequest) shadowOutcome {
	plan, err := client.Plan(ctx, req)
	if plan == nil {
		return shadowOutcomeFrom(nil, err)
	}
	return shadowOutcomeFrom(plan.api, err)
}

func runShadowTDX(ctx context.Context, server *MaasServer, req *pb.MaasPlanRequest) shadowOutcome {
	api, err := server.fetch(ctx, req)
	return shadowOutcomeFrom(api, err)
}

// shadowOutcomeFrom folds "no route" into an empty answer rather than an error.
// Both backends signal it as a 404, and counting it as a failure would double
// count the very thing being measured.
func shadowOutcomeFrom(api *tdxAPIResponse, err error) shadowOutcome {
	if errors.Is(err, errMaasNoRoute) {
		return shadowOutcome{}
	}
	if err != nil {
		return shadowOutcome{err: err}
	}
	if api == nil || len(api.Data.Routes) == 0 {
		return shadowOutcome{}
	}
	best := api.Data.Routes[0]
	return shadowOutcome{
		routes:     len(api.Data.Routes),
		travelTime: best.TravelTime,
		transfers:  best.Transfers,
	}
}

func describeShadow(outcome shadowOutcome) string {
	switch {
	case outcome.err != nil:
		return "ERR " + strings.SplitN(outcome.err.Error(), "\n", 2)[0]
	case outcome.routes == 0:
		return "none"
	default:
		return fmt.Sprintf("%d routes, %dm, %d transfers",
			outcome.routes, outcome.travelTime/60, outcome.transfers)
	}
}

type shadowPair struct {
	from shadowPlace
	to   shadowPlace
}

// shadowPlaces draws candidate endpoints from the stop tables. Metro, rail and
// bus stops are all included because they sit in different parts of the street
// network -- a corpus of rail stations alone would only ever exercise the
// best-connected coordinates in the country.
func shadowPlaces(ctx context.Context, db *pgxpool.Pool) ([]shadowPlace, error) {
	const query = `
	SELECT name, city, ST_Y(position) AS lat, ST_X(position) AS lon
	  FROM bus_station_groups WHERE position IS NOT NULL
	UNION ALL
	SELECT name, city, ST_Y(stationposition), ST_X(stationposition)
	  FROM mrt_station WHERE stationposition IS NOT NULL
	UNION ALL
	SELECT name, city, ST_Y(geom), ST_X(geom)
	  FROM tra_stations WHERE geom IS NOT NULL`
	rows, err := db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var places []shadowPlace
	for rows.Next() {
		var place shadowPlace
		if err := rows.Scan(&place.name, &place.city, &place.lat, &place.lon); err != nil {
			return nil, err
		}
		place.region = shadowRegionOf(place.city)
		places = append(places, place)
	}
	return places, rows.Err()
}

// shadowPairs builds the corpus, stratified so Taichung and the south each
// clear their floor. Origins are drawn per region and destinations drawn freely
// from anywhere, which is what makes cross-city trips -- the ones most likely
// to expose a calendar or timetable hole -- part of the sample rather than an
// afterthought.
func shadowPairs(places []shadowPlace) []shadowPair {
	random := rand.New(rand.NewSource(_shadowSeed))
	byRegion := map[string][]shadowPlace{}
	for _, place := range places {
		byRegion[place.region] = append(byRegion[place.region], place)
	}

	quota := map[string]int{
		"taichung": int(_shadowMinRegionShare * _shadowPairs),
		"south":    int(_shadowMinRegionShare * _shadowPairs),
	}
	quota["north"] = _shadowPairs - quota["taichung"] - quota["south"]

	pairs := make([]shadowPair, 0, _shadowPairs)
	for _, region := range sortedKeys(quota) {
		origins := byRegion[region]
		if len(origins) == 0 {
			continue
		}
		for range quota[region] {
			from := origins[random.Intn(len(origins))]
			to := places[random.Intn(len(places))]
			// A pair with the same endpoint twice measures nothing.
			if from.name == to.name {
				continue
			}
			pairs = append(pairs, shadowPair{from: from, to: to})
		}
	}
	return pairs
}

// reportShadowComposition states what was actually sampled. A run whose corpus
// silently fell short of the regional floors would report a rate that says
// nothing about the places the feed is weakest, so the composition is printed
// next to the result rather than assumed from the quota.
func reportShadowComposition(t *testing.T, pairs []shadowPair) {
	t.Helper()
	counts := map[string]int{}
	for _, pair := range pairs {
		counts[pair.from.region]++
	}
	for _, region := range sortedKeys(counts) {
		share := float64(counts[region]) / float64(len(pairs))
		t.Logf("corpus %-10s %3d (%.0f%%)", region, counts[region], 100*share)
		if (region == "taichung" || region == "south") && share < _shadowMinRegionShare {
			t.Fatalf("%s is %.0f%% of the corpus, floor is %.0f%%",
				region, 100*share, 100*_shadowMinRegionShare)
		}
	}
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// newShadowCache is a cache that never hits. The comparison must measure the
// upstream, and a Redis-backed run would silently answer from a previous one.
type shadowCache struct{}

func newShadowCache() *shadowCache { return &shadowCache{} }

func (*shadowCache) Get(context.Context, string) ([]byte, error) {
	return nil, errors.New("shadow comparison does not cache")
}

func (*shadowCache) Set(context.Context, string, []byte, time.Duration) error { return nil }

// shadowTokenStore holds the TDX bearer token for the life of the run. Not
// concurrency-safe, and does not need to be: the comparison is deliberately
// sequential so it paces both upstreams.
type shadowTokenStore struct {
	values map[string]string
}

func (s *shadowTokenStore) Get(_ context.Context, key string) (string, error) {
	return s.values[key], nil
}

func (s *shadowTokenStore) Set(_ context.Context, key, value string, _ time.Duration) error {
	s.values[key] = value
	return nil
}

func (s *shadowTokenStore) Del(_ context.Context, keys ...string) error {
	for _, key := range keys {
		delete(s.values, key)
	}
	return nil
}
