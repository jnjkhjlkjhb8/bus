package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-resty/resty/v2"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/pashagolub/pgxmock/v4"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type maasTDXStore struct {
	token  string
	getErr error
	gets   int32
}

func (s *maasTDXStore) Get(string) (string, error) {
	atomic.AddInt32(&s.gets, 1)
	if s.getErr != nil {
		return "", s.getErr
	}
	return s.token, nil
}

func (*maasTDXStore) Set(string, string, time.Duration) error { return nil }
func (*maasTDXStore) Del(...string) error                     { return nil }

func TestMaasCanceledRequestDoesNotRetryOrReachUpstream(t *testing.T) {
	var hits int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer upstream.Close()

	store := &maasTDXStore{token: "tok"}
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: store, IMSKey: shared.TDXLegacyIMSKey})
	client := newMaasServer(nil, nil, tdx).maasClient.SetBaseURL(upstream.URL)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	started := time.Now()
	_, err := client.R().SetContext(ctx).Get("/routing")
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("MaaS canceled error = %v, want context.Canceled", err)
	}
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Fatalf("canceled MaaS request took %v", elapsed)
	}
	if got := atomic.LoadInt32(&hits); got != 0 {
		t.Fatalf("upstream hits = %d, want 0", got)
	}
}

func TestMaasAuthCacheErrorIsNotRetried(t *testing.T) {
	var hits int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer upstream.Close()

	cacheErr := errors.New("token cache unavailable")
	store := &maasTDXStore{getErr: cacheErr}
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: store, IMSKey: shared.TDXLegacyIMSKey})
	client := newMaasServer(nil, nil, tdx).maasClient.
		SetBaseURL(upstream.URL).
		SetRetryWaitTime(time.Nanosecond).
		SetRetryMaxWaitTime(time.Nanosecond)
	_, err := client.R().SetContext(context.Background()).Get("/routing")
	if !errors.Is(err, cacheErr) {
		t.Fatalf("MaaS auth error = %v, want %v", err, cacheErr)
	}
	if got := atomic.LoadInt32(&store.gets); got != 1 {
		t.Fatalf("token cache reads = %d, want 1 (no retry)", got)
	}
	if got := atomic.LoadInt32(&hits); got != 0 {
		t.Fatalf("upstream hits = %d, want 0", got)
	}
}

func TestMaasTimeParam(t *testing.T) {
	now := time.Date(2026, 7, 11, 23, 0, 0, 0, time.Local)
	layout := "2006-01-02T15:04:05"

	// TDX requires both depart and arrival present (else 40001); every case
	// must return the two equal and non-empty.
	assertBoth := func(t *testing.T, depart, arrival, want string) {
		t.Helper()
		if depart != arrival {
			t.Fatalf("depart %q != arrival %q, TDX needs both equal", depart, arrival)
		}
		if want != "" && depart != want {
			t.Fatalf("got %q, want %q", depart, want)
		}
	}

	t.Run("arriveBy sends the requested time with padded seconds", func(t *testing.T) {
		d, a := maasTimeParam("2026-07-12", "08:30", true, now)
		assertBoth(t, d, a, "2026-07-12T08:30:00")
	})

	t.Run("future depart is passed through unchanged", func(t *testing.T) {
		d, a := maasTimeParam("2026-07-11", "23:30", false, now)
		assertBoth(t, d, a, "2026-07-11T23:30:00")
	})

	// A depart at/before now must be bumped into the future to avoid TDX 20001.
	for _, tt := range []struct{ name, date, tm string }{
		{"now", "2026-07-11", "23:00"},
		{"past", "2026-07-11", "22:00"},
	} {
		t.Run("depart "+tt.name+" is bumped into the future", func(t *testing.T) {
			d, a := maasTimeParam(tt.date, tt.tm, false, now)
			assertBoth(t, d, a, "")
			got, err := time.ParseInLocation(layout, d, time.Local)
			if err != nil {
				t.Fatalf("unparseable depart %q: %v", d, err)
			}
			if !got.After(now) {
				t.Fatalf("depart %v not after now %v", got, now)
			}
		})
	}

	t.Run("unparseable time falls through unchanged", func(t *testing.T) {
		d, a := maasTimeParam("", "", false, now)
		assertBoth(t, d, a, "T")
	})
}

func TestConvertBatchesIdentityAndFareQueries(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery(`(?s)WITH input AS.*bus_station_stop_map`).
		WithArgs(
			[]int32{0, 2, 3},
			[]string{"A", "C", "E"},
			[]string{"B", "D", "F"},
			[]string{"1", "2", "3"},
			[]string{"1", "2", "3"},
			[]string{"", "", ""},
		).
		WillReturnRows(pgxmock.NewRows([]string{
			"section_index", "sub_route_uid", "direction", "departure_stop_uid", "arrival_stop_uid", "match_count",
		}).
			AddRow(int32(0), "BUS-1", int32(0), "STOP-A", "STOP-B", int64(1)).
			AddRow(int32(2), "BUS-2", int32(1), "STOP-C", "STOP-D", int64(2)))
	db.ExpectQuery(`(?s)WITH input AS.*destination\.system = origin\.system.*m\.system = origin\.system.*MIN\(fare\).*WHERE fare > 0`).
		WithArgs(
			[]int32{1, 4, 5, 6},
			[]string{"mrt", "tra", "thsr", "subway"},
			[]string{"台北", "台北", "台北", "西門"},
			[]string{"西門", "台中", "左營", "龍山寺"},
		).
		WillReturnRows(pgxmock.NewRows([]string{"section_index", "fare"}).
			AddRow(int32(1), int32(25)).
			AddRow(int32(1), int32(20)).
			AddRow(int32(4), int32(41)).
			AddRow(int32(4), int32(41)).
			AddRow(int32(5), int32(0)).
			AddRow(int32(5), int32(700)).
			AddRow(int32(6), int32(-10)).
			AddRow(int32(6), int32(30)))

	section := func(mode, name, from, to string) tdxSection {
		return tdxSection{
			Type:      "transit",
			Transport: tdxTransport{Mode: mode, Name: name, ShortName: name},
			Departure: tdxPlaceInfo{Place: tdxPlace{Name: from}},
			Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: to}},
		}
	}
	api := &tdxAPIResponse{}
	api.Data.Routes = []tdxRoute{{Sections: []tdxSection{
		section("BUS", "1", "A", "B"),
		section("MRT", "", "台北", "西門"),
		section("HighwayBus", "2", "C", "D"),
		section("BUS", "3", "E", "F"),
		section("TRA", "", "台北", "台中"),
		section("THSR", "", "台北", "左營"),
		section("SUBWAY", "", "西門", "龍山寺"),
	}}}

	out := convert(context.Background(), db, nil, api)
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatalf("database queries were not batched to a constant count: %v", err)
	}
	sections := out.GetRoutes()[0].GetSections()
	if got := sections[0].GetNotificationIdentity().GetRouteKey(); got != "BUS-1" {
		t.Fatalf("first bus route key = %q, want BUS-1", got)
	}
	if sections[2].GetNotificationIdentity().GetSupported() {
		t.Fatalf("ambiguous second bus identity must be unsupported: %v", sections[2].GetNotificationIdentity())
	}
	if sections[3].GetNotificationIdentity().GetSupported() {
		t.Fatalf("unmatched third bus identity must be unsupported: %v", sections[3].GetNotificationIdentity())
	}
	wantFares := map[int]int32{1: 20, 4: 41, 5: 700, 6: 30}
	for index, want := range wantFares {
		if got := sections[index].GetFare(); got != want {
			t.Fatalf("section %d fare = %d, want %d", index, got, want)
		}
	}
	if got := out.GetRoutes()[0].GetTotalFare(); got != 791 {
		t.Fatalf("total fare = %d, want 791", got)
	}
}

type cancelAfterAcquireContext struct {
	context.Context
	errCalls atomic.Int32
}

func (c *cancelAfterAcquireContext) Err() error {
	if c.errCalls.Add(1) >= 2 {
		return context.Canceled
	}
	return nil
}

func TestMaasResourceInterceptorChecksCancellationBeforeAndAfterAcquire(t *testing.T) {
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }

	t.Run("already canceled does not consume rate quota", func(t *testing.T) {
		interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
			RateLimit: 1, RateWindow: time.Minute, MaxConcurrent: 1, Timeout: time.Second,
		})
		peerCtx := limiterContext("203.0.113.40:1234")
		canceled, cancel := context.WithCancel(peerCtx)
		cancel()
		if _, err := interceptor(canceled, nil, info, handler); status.Code(err) != codes.Canceled {
			t.Fatalf("canceled call code = %v", status.Code(err))
		}
		if _, err := interceptor(peerCtx, nil, info, handler); err != nil {
			t.Fatalf("canceled call consumed quota: %v", err)
		}
	})

	t.Run("cancellation immediately after acquire skips handler and releases slot", func(t *testing.T) {
		interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
			RateLimit: 10, RateWindow: time.Minute, MaxConcurrent: 1, Timeout: time.Second,
		})
		ctx := &cancelAfterAcquireContext{Context: limiterContext("203.0.113.41:1234")}
		called := false
		_, err := interceptor(ctx, nil, info, func(context.Context, interface{}) (interface{}, error) {
			called = true
			return "unexpected", nil
		})
		if status.Code(err) != codes.Canceled || called {
			t.Fatalf("post-acquire cancellation = (code=%v called=%v)", status.Code(err), called)
		}
		if _, err := interceptor(limiterContext("203.0.113.42:1234"), nil, info, handler); err != nil {
			t.Fatalf("post-acquire cancellation leaked slot: %v", err)
		}
	})
}

func TestMaasPlanCanceledSingleflightFollowerReleasesInterceptorSlot(t *testing.T) {
	upstreamStarted := make(chan struct{})
	releaseUpstream := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		select {
		case <-upstreamStarted:
		default:
			close(upstreamStarted)
		}
		<-releaseUpstream
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"result":"success","data":{"routes":[]}}`)
	}))
	defer upstream.Close()

	tdx := shared.NewTDXClient(shared.TDXConfig{Store: &maasTDXStore{token: "tok"}, IMSKey: shared.TDXLegacyIMSKey})
	server := newMaasServer(nil, nil, tdx)
	server.maasClient.SetBaseURL(upstream.URL).SetRetryCount(0)
	interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
		RateLimit: 100, RateWindow: time.Minute, MaxConcurrent: 2, Timeout: 3 * time.Second,
	})
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	req := &pb.MaasPlanRequest{FromLat: 25.0, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6, Date: "2027-01-01", Time: "08:00"}
	planHandler := func(ctx context.Context, request interface{}) (interface{}, error) {
		return server.Plan(ctx, request.(*pb.MaasPlanRequest))
	}

	leaderDone := make(chan error, 1)
	go func() {
		_, err := interceptor(limiterContext("203.0.113.50:1234"), req, info, planHandler)
		leaderDone <- err
	}()
	<-upstreamStarted

	followerCtx, cancelFollower := context.WithCancel(limiterContext("203.0.113.51:1234"))
	followerDone := make(chan error, 1)
	go func() {
		_, err := interceptor(followerCtx, req, info, planHandler)
		followerDone <- err
	}()
	time.Sleep(20 * time.Millisecond)
	cancelFollower()

	select {
	case err := <-followerDone:
		if status.Code(err) != codes.Canceled {
			close(releaseUpstream)
			<-leaderDone
			t.Fatalf("follower code = %v, want %v", status.Code(err), codes.Canceled)
		}
	case <-time.After(250 * time.Millisecond):
		close(releaseUpstream)
		<-leaderDone
		<-followerDone
		t.Fatal("canceled singleflight follower stayed blocked behind leader")
	}

	if _, err := interceptor(limiterContext("203.0.113.52:1234"), nil, info,
		func(context.Context, interface{}) (interface{}, error) { return "slot available", nil }); err != nil {
		close(releaseUpstream)
		<-leaderDone
		t.Fatalf("canceled follower did not release interceptor slot: %v", err)
	}
	select {
	case err := <-leaderDone:
		t.Fatalf("leader finished before upstream release: %v", err)
	default:
	}
	close(releaseUpstream)
	if err := <-leaderDone; err != nil {
		t.Fatalf("leader failed: %v", err)
	}
}

func TestWalkRouteFallsBackWithoutOSRM(t *testing.T) {
	// A nil client or zero coordinates must report ok=false so the caller keeps
	// the fixed TDX walk estimate and leaves the path and steps empty.
	from := &pb.Location{Lat: 25.0, Lng: 121.5}
	to := &pb.Location{Lat: 25.1, Lng: 121.6}
	if _, _, _, ok := walkRoute(context.Background(), nil, from, to); ok {
		t.Fatal("nil OSRM client must fall back")
	}
	zero := &pb.Location{}
	if _, _, _, ok := walkRoute(context.Background(), resty.New(), zero, to); ok {
		t.Fatal("zero origin must fall back")
	}
	if _, _, _, ok := walkRoute(context.Background(), resty.New(), from, zero); ok {
		t.Fatal("zero destination must fall back")
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// osrmClientReturning builds a resty client whose transport short-circuits every
// request with a canned response, so the OSRM URL (which points at the internal
// osrm:5000 host) never has to resolve.
func osrmClientReturning(status int, body string) *resty.Client {
	c := resty.New()
	c.SetTransport(roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: status,
			Body:       io.NopCloser(strings.NewReader(body)),
			Header:     http.Header{"Content-Type": []string{"application/json"}},
		}, nil
	}))
	return c
}

const osrmTransferRoute = `{
  "code":"Ok",
  "routes":[{
    "duration":222.5,
    "geometry":{"coordinates":[[121.50,25.00],[121.51,25.01],[121.52,25.02]]},
    "legs":[{"steps":[
      {"distance":50,"duration":40,"name":"忠孝東路四段","maneuver":{"type":"depart","modifier":"","location":[121.50,25.00]}},
      {"distance":30,"duration":25,"name":"市民大道三段","maneuver":{"type":"turn","modifier":"left","location":[121.51,25.01]}},
      {"distance":0,"duration":0,"name":"","maneuver":{"type":"arrive","modifier":"","location":[121.52,25.02]}}
    ]}]
  }]
}`

// A transfer walk (a middle section, not first/last) must get its TDX duration
// replaced by the OSRM time and gain the geometry plus composed steps.
func TestConvertWalkRouteMapsTransferSection(t *testing.T) {
	api := &tdxAPIResponse{}
	api.Data.Routes = []tdxRoute{{
		Sections: []tdxSection{
			{Type: "transit", Transport: tdxTransport{Mode: "BUS"},
				Departure: tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.00, Lng: 121.50}}},
				Arrival:   tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.00, Lng: 121.50}}}},
			{Type: "pedestrian", Transport: tdxTransport{Mode: "pedestrian"},
				TravelSummary: tdxSummary{Duration: 600},
				Departure:     tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.00, Lng: 121.50}}},
				Arrival:       tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.02, Lng: 121.52}}}},
			{Type: "transit", Transport: tdxTransport{Mode: "BUS"},
				Departure: tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.02, Lng: 121.52}}},
				Arrival:   tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.02, Lng: 121.52}}}},
		},
	}}

	out := convert(context.Background(), nil, osrmClientReturning(200, osrmTransferRoute), api)
	walk := out.Routes[0].Sections[1]
	if walk.TravelSummary.Duration != 222 {
		t.Fatalf("duration = %d, want 222 (OSRM time)", walk.TravelSummary.Duration)
	}
	if len(walk.WalkPath) != 3 {
		t.Fatalf("walkPath len = %d, want 3", len(walk.WalkPath))
	}
	if walk.WalkPath[0].Lat != 25.00 || walk.WalkPath[0].Lng != 121.50 {
		t.Fatalf("first path point = %v, want lat 25.00 lng 121.50", walk.WalkPath[0])
	}
	wantSteps := []string{"沿忠孝東路四段出發", "左轉進入市民大道三段", "抵達目的地"}
	if len(walk.WalkSteps) != len(wantSteps) {
		t.Fatalf("walkSteps len = %d, want %d", len(walk.WalkSteps), len(wantSteps))
	}
	for i, want := range wantSteps {
		if walk.WalkSteps[i].Instruction != want {
			t.Fatalf("step[%d] = %q, want %q", i, walk.WalkSteps[i].Instruction, want)
		}
	}
	if walk.WalkSteps[1].ManeuverType != "turn" || walk.WalkSteps[1].Modifier != "left" {
		t.Fatalf("raw maneuver not preserved: %+v", walk.WalkSteps[1])
	}
}

// An OSRM failure (non-Ok response) leaves the walk section untouched: the TDX
// duration stays and no path or steps are attached. The plan never fails.
func TestConvertWalkRouteFailureLeavesSectionUntouched(t *testing.T) {
	api := &tdxAPIResponse{}
	api.Data.Routes = []tdxRoute{{
		Sections: []tdxSection{
			{Type: "pedestrian", Transport: tdxTransport{Mode: "pedestrian"},
				TravelSummary: tdxSummary{Duration: 600},
				Departure:     tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.00, Lng: 121.50}}},
				Arrival:       tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.02, Lng: 121.52}}}},
		},
	}}

	out := convert(context.Background(), nil, osrmClientReturning(500, `{"code":"NoRoute"}`), api)
	walk := out.Routes[0].Sections[0]
	if walk.TravelSummary.Duration != 600 {
		t.Fatalf("duration = %d, want 600 (TDX kept)", walk.TravelSummary.Duration)
	}
	if len(walk.WalkPath) != 0 || len(walk.WalkSteps) != 0 {
		t.Fatalf("failed OSRM must leave path/steps empty: path=%d steps=%d",
			len(walk.WalkPath), len(walk.WalkSteps))
	}
}

func TestConvertWalkRoutesAreBoundedConcurrentAndOrderStable(t *testing.T) {
	const walkCount = 9
	var active, peak int32
	client := resty.New()
	client.SetTransport(roundTripFunc(func(request *http.Request) (*http.Response, error) {
		current := atomic.AddInt32(&active, 1)
		defer atomic.AddInt32(&active, -1)
		for {
			observed := atomic.LoadInt32(&peak)
			if current <= observed || atomic.CompareAndSwapInt32(&peak, observed, current) {
				break
			}
		}
		var fromLng float64
		_, _ = fmt.Sscanf(strings.TrimPrefix(request.URL.Path, "/route/v1/foot/"), "%f,", &fromLng)
		index := int(math.Round((fromLng - 121) * 100))
		time.Sleep(time.Duration(walkCount-index) * 5 * time.Millisecond)
		body := fmt.Sprintf(`{"code":"Ok","routes":[{"duration":%d,"geometry":{"coordinates":[[%f,25],[%f,25.01]]},"legs":[]}]}`,
			100+index, fromLng, fromLng+0.001)
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(body)),
			Header:     http.Header{"Content-Type": []string{"application/json"}},
		}, nil
	}))

	api := &tdxAPIResponse{}
	sections := make([]tdxSection, walkCount)
	for index := range sections {
		lng := 121 + float64(index)/100
		sections[index] = tdxSection{
			Type:          "pedestrian",
			Transport:     tdxTransport{Mode: "pedestrian"},
			TravelSummary: tdxSummary{Duration: 600},
			Departure:     tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25, Lng: lng}}},
			Arrival:       tdxPlaceInfo{Place: tdxPlace{Location: tdxLocation{Lat: 25.01, Lng: lng + 0.001}}},
		}
	}
	api.Data.Routes = []tdxRoute{{Sections: sections}}

	out := convert(context.Background(), nil, client, api)
	if got := atomic.LoadInt32(&peak); got <= 1 || got > 4 {
		t.Fatalf("peak OSRM concurrency = %d, want 2..4", got)
	}
	for index, section := range out.GetRoutes()[0].GetSections() {
		if got, want := section.GetTravelSummary().GetDuration(), int64(100+index); got != want {
			t.Fatalf("section %d duration = %d, want %d (results must retain input order)", index, got, want)
		}
	}
}

// clampInt guards the TDX plan-request parameters; a wrong bound sends invalid
// values upstream, a broken zero-default breaks every old client that omits
// the field.
func TestClampInt(t *testing.T) {
	tests := []struct {
		name                   string
		v, min, max, def, want int32
	}{
		{"unset falls back to default when 0 invalid", 0, 1, 10, 5, 5},
		{"zero kept when 0 within range", 0, 0, 10, 5, 0},
		{"zero kept when range spans negative", 0, -5, 5, 3, 0},
		{"below min clamps up", -3, 1, 10, 5, 1},
		{"above max clamps down", 99, 1, 10, 5, 10},
		{"in range passes through", 7, 1, 10, 5, 7},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := clampInt(tt.v, tt.min, tt.max, tt.def); got != tt.want {
				t.Fatalf("clampInt(%d,%d,%d,%d) = %d, want %d", tt.v, tt.min, tt.max, tt.def, got, tt.want)
			}
		})
	}
}

// A cache-key collision between different plan requests would serve one user
// another user's journey plan; identical requests must hit the same key or the
// cache never helps.
func TestMaasKeyIdentityAndCollision(t *testing.T) {
	base := func() *pb.MaasPlanRequest {
		return &pb.MaasPlanRequest{
			FromLat: 25.0478, FromLon: 121.5170, ToLat: 25.0330, ToLon: 121.5654,
			Date: "2026-07-11", Time: "08:00", Top: 5,
		}
	}
	first, second := maasKey(base()), maasKey(base())
	if first != second {
		t.Fatal("identical requests must produce the same cache key")
	}
	mutations := map[string]func(r *pb.MaasPlanRequest){
		"destination": func(r *pb.MaasPlanRequest) { r.ToLat += 0.001 },
		"date":        func(r *pb.MaasPlanRequest) { r.Date = "2026-07-12" },
		"arrive_by":   func(r *pb.MaasPlanRequest) { r.ArriveBy = true },
		"modes":       func(r *pb.MaasPlanRequest) { r.TransitModes = []int32{3} },
	}
	seen := map[string]string{maasKey(base()): "base"}
	for name, mutate := range mutations {
		r := base()
		mutate(r)
		key := maasKey(r)
		if prev, dup := seen[key]; dup {
			t.Fatalf("cache key collision between %q and %q", name, prev)
		}
		seen[key] = name
	}
}
