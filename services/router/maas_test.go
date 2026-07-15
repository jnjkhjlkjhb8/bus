package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	legacyredis "github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/pashagolub/pgxmock/v4"
	redisv9 "github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
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

var errMaasCacheMiss = errors.New("cache miss")

type controlledMaasCache struct {
	mu sync.Mutex

	data map[string][]byte

	getCalls  atomic.Int32
	setCalls  atomic.Int32
	getOnce   sync.Once
	setOnce   sync.Once
	getStart  chan struct{}
	setStart  chan struct{}
	getBlock  <-chan struct{}
	setBlock  <-chan struct{}
	getCtxEnd chan struct{}
	setCtxEnd chan struct{}
}

func newControlledMaasCache() *controlledMaasCache {
	return &controlledMaasCache{data: make(map[string][]byte)}
}

func (c *controlledMaasCache) Get(ctx context.Context, key string) ([]byte, error) {
	c.getCalls.Add(1)
	if c.getStart != nil {
		c.getOnce.Do(func() { close(c.getStart) })
	}
	if c.getBlock != nil {
		select {
		case <-c.getBlock:
		case <-ctx.Done():
			if c.getCtxEnd != nil {
				close(c.getCtxEnd)
			}
			return nil, ctx.Err()
		}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	value, ok := c.data[key]
	if !ok {
		return nil, errMaasCacheMiss
	}
	return append([]byte(nil), value...), nil
}

func (c *controlledMaasCache) Set(ctx context.Context, key string, value []byte, _ time.Duration) error {
	c.setCalls.Add(1)
	if c.setStart != nil {
		c.setOnce.Do(func() { close(c.setStart) })
	}
	if c.setBlock != nil {
		select {
		case <-c.setBlock:
		case <-ctx.Done():
			if c.setCtxEnd != nil {
				close(c.setCtxEnd)
			}
			return ctx.Err()
		}
	}
	c.mu.Lock()
	c.data[key] = append([]byte(nil), value...)
	c.mu.Unlock()
	return nil
}

type doneObservedContext struct {
	context.Context
	once     sync.Once
	observed chan struct{}
}

type pendingDeadlineContext struct {
	context.Context
	deadline time.Time
}

func (c pendingDeadlineContext) Deadline() (time.Time, bool) { return c.deadline, true }

type fakeTimeoutError struct{}

func (fakeTimeoutError) Error() string   { return "i/o timeout" }
func (fakeTimeoutError) Timeout() bool   { return true }
func (fakeTimeoutError) Temporary() bool { return true }

type commandCompletionHook struct {
	target string
	done   chan struct{}
	once   sync.Once
}

func (h *commandCompletionHook) DialHook(next redisv9.DialHook) redisv9.DialHook {
	return next
}

func (h *commandCompletionHook) ProcessHook(next redisv9.ProcessHook) redisv9.ProcessHook {
	return func(ctx context.Context, command redisv9.Cmder) error {
		err := next(ctx, command)
		if strings.EqualFold(command.Name(), h.target) {
			h.once.Do(func() { close(h.done) })
		}
		return err
	}
}

func (h *commandCompletionHook) ProcessPipelineHook(next redisv9.ProcessPipelineHook) redisv9.ProcessPipelineHook {
	return next
}

type blockingRedisEndpoint struct {
	address           string
	commandStarted    chan struct{}
	connectionStopped chan struct{}
	listener          net.Listener
}

func startBlockingRedisEndpoint(t *testing.T, targetCommand string) *blockingRedisEndpoint {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	endpoint := &blockingRedisEndpoint{
		address: listener.Addr().String(), commandStarted: make(chan struct{}),
		connectionStopped: make(chan struct{}), listener: listener,
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		connection, err := listener.Accept()
		if err != nil {
			return
		}
		defer connection.Close()
		reader := bufio.NewReader(connection)
		writer := bufio.NewWriter(connection)
		for {
			command, err := readRESPCommand(reader)
			if err != nil {
				return
			}
			name := strings.ToLower(command[0])
			if name == strings.ToLower(targetCommand) {
				close(endpoint.commandStarted)
				_, _ = reader.ReadByte()
				close(endpoint.connectionStopped)
				return
			}
			if name == "hello" {
				_, _ = writer.WriteString("-ERR unknown command 'hello'\r\n")
			} else {
				_, _ = writer.WriteString("+OK\r\n")
			}
			if err := writer.Flush(); err != nil {
				return
			}
		}
	}()
	return endpoint
}

func readRESPCommand(reader *bufio.Reader) ([]string, error) {
	line, err := reader.ReadString('\n')
	if err != nil {
		return nil, err
	}
	if len(line) < 3 || line[0] != '*' {
		return nil, fmt.Errorf("unexpected RESP array header %q", line)
	}
	count, err := strconv.Atoi(strings.TrimSpace(line[1:]))
	if err != nil {
		return nil, err
	}
	parts := make([]string, count)
	for index := range parts {
		lengthLine, err := reader.ReadString('\n')
		if err != nil {
			return nil, err
		}
		if len(lengthLine) < 3 || lengthLine[0] != '$' {
			return nil, fmt.Errorf("unexpected RESP bulk header %q", lengthLine)
		}
		length, err := strconv.Atoi(strings.TrimSpace(lengthLine[1:]))
		if err != nil {
			return nil, err
		}
		value := make([]byte, length+2)
		if _, err := io.ReadFull(reader, value); err != nil {
			return nil, err
		}
		parts[index] = string(value[:length])
	}
	return parts, nil
}

func (c *doneObservedContext) Done() <-chan struct{} {
	c.once.Do(func() { close(c.observed) })
	return c.Context.Done()
}

func TestMaasCanceledRequestDoesNotRetryOrReachUpstream(t *testing.T) {
	var hits int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer upstream.Close()

	store := &maasTDXStore{token: "tok"}
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: store, IMSKey: shared.TDXLegacyIMSKey})
	client := newMaasServerWithCache(newControlledMaasCache(), nil, tdx, defaultMaasSharedWorkConfig).maasClient.SetBaseURL(upstream.URL)
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
	client := newMaasServerWithCache(newControlledMaasCache(), nil, tdx, defaultMaasSharedWorkConfig).maasClient.
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

func TestRedisMaasCacheCopiesLegacyConnectionOptionsAndOwnsClient(t *testing.T) {
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS12, ServerName: "redis.internal"}
	legacyOptions := &legacyredis.Options{
		Network: "tcp", Addr: "redis.internal:6380", Password: "password", DB: 7,
		MaxRetries: 2, MinRetryBackoff: 11 * time.Millisecond, MaxRetryBackoff: 29 * time.Millisecond,
		DialTimeout: 31 * time.Millisecond, ReadTimeout: 37 * time.Millisecond, WriteTimeout: 41 * time.Millisecond,
		PoolSize: 9, MinIdleConns: 3, PoolTimeout: 43 * time.Millisecond,
		MaxConnAge: 47 * time.Millisecond, IdleTimeout: 53 * time.Millisecond, TLSConfig: tlsConfig,
	}
	mappedOptions := redisMaasOptions(legacyOptions)
	if mappedOptions.ReadTimeout != legacyOptions.ReadTimeout || mappedOptions.WriteTimeout != legacyOptions.WriteTimeout {
		t.Fatalf("positive timeout mapping = read %v write %v, want %v/%v", mappedOptions.ReadTimeout, mappedOptions.WriteTimeout, legacyOptions.ReadTimeout, legacyOptions.WriteTimeout)
	}
	cache := newRedisMaasCache(legacyOptions)
	options := cache.client.Options()
	if options.Network != legacyOptions.Network || options.Addr != legacyOptions.Addr ||
		options.Username != "" || options.Password != legacyOptions.Password || options.DB != legacyOptions.DB {
		t.Fatalf("connection identity was not copied: %+v", options)
	}
	if options.DialTimeout != legacyOptions.DialTimeout || options.ReadTimeout != legacyOptions.ReadTimeout ||
		options.WriteTimeout != legacyOptions.WriteTimeout || options.PoolTimeout != legacyOptions.PoolTimeout {
		t.Fatalf("finite timeouts were not copied: %+v", options)
	}
	if options.PoolSize != legacyOptions.PoolSize || options.MinIdleConns != legacyOptions.MinIdleConns ||
		options.ConnMaxLifetime != legacyOptions.MaxConnAge || options.ConnMaxIdleTime != legacyOptions.IdleTimeout {
		t.Fatalf("pool settings were not copied: %+v", options)
	}
	if options.Protocol != 2 || !options.ContextTimeoutEnabled || !options.DisableIdentity {
		t.Fatalf("MaaS Redis safety options are not enabled: %+v", options)
	}
	if options.TLSConfig == nil || options.TLSConfig == tlsConfig ||
		options.TLSConfig.ServerName != tlsConfig.ServerName || options.TLSConfig.MinVersion != tlsConfig.MinVersion {
		t.Fatalf("TLS config was not safely cloned: got=%p want-clone-of=%p", options.TLSConfig, tlsConfig)
	}
	if err := cache.Close(); err != nil {
		t.Fatalf("owned Redis client close failed: %v", err)
	}
	if err := cache.client.Ping(context.Background()).Err(); !errors.Is(err, redisv9.ErrClosed) {
		t.Fatalf("owned Redis client remained usable after close: %v", err)
	}
}

func TestRedisMaasCachePreservesEffectiveDisabledLegacyTimeouts(t *testing.T) {
	options := redisMaasOptions(&legacyredis.Options{
		Addr:         "redis.internal:6379",
		ReadTimeout:  0,
		WriteTimeout: 0,
	})
	if options.ReadTimeout != -1 || options.WriteTimeout != -1 {
		t.Fatalf("effective disabled v6 timeouts became read=%v write=%v, want -1/-1 in v9", options.ReadTimeout, options.WriteTimeout)
	}
}

func TestRedisContextErrorHandlesSocketDeadlineTimerRace(t *testing.T) {
	timeoutErr := fakeTimeoutError{}
	pastDeadline := pendingDeadlineContext{Context: context.Background(), deadline: time.Now().Add(-time.Second)}
	if err := redisContextError(pastDeadline, timeoutErr); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("elapsed context deadline error = %v, want %v", err, context.DeadlineExceeded)
	}
	futureDeadline := pendingDeadlineContext{Context: context.Background(), deadline: time.Now().Add(time.Hour)}
	if err := redisContextError(futureDeadline, timeoutErr); !errors.Is(err, timeoutErr) {
		t.Fatalf("early Redis timeout error = %v, want original %v", err, timeoutErr)
	}
}

func TestRedisMaasCacheCommandsEndBeforeContextErrorReturns(t *testing.T) {
	for _, test := range []struct {
		name      string
		command   string
		invoke    func(context.Context, *redisMaasCache) error
		newCtx    func() (context.Context, context.CancelFunc)
		wantError error
	}{
		{
			name: "Get deadline", command: "get",
			invoke: func(ctx context.Context, cache *redisMaasCache) error {
				_, err := cache.Get(ctx, "blocked")
				return err
			},
			newCtx: func() (context.Context, context.CancelFunc) {
				return context.WithTimeout(context.Background(), 80*time.Millisecond)
			},
			wantError: context.DeadlineExceeded,
		},
		{
			name: "Set deadline", command: "set",
			invoke: func(ctx context.Context, cache *redisMaasCache) error {
				return cache.Set(ctx, "blocked", []byte("value"), time.Minute)
			},
			newCtx: func() (context.Context, context.CancelFunc) {
				return context.WithTimeout(context.Background(), 80*time.Millisecond)
			},
			wantError: context.DeadlineExceeded,
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			endpoint := startBlockingRedisEndpoint(t, test.command)
			cache := newRedisMaasCache(&legacyredis.Options{
				Network: "tcp", Addr: endpoint.address, MaxRetries: -1,
				DialTimeout: time.Second, ReadTimeout: -1, WriteTimeout: -1,
				PoolSize: 1, PoolTimeout: time.Second,
			})
			defer cache.Close()
			processDone := make(chan struct{})
			cache.client.AddHook(&commandCompletionHook{target: test.command, done: processDone})
			ctx, cancel := test.newCtx()
			defer cancel()
			result := make(chan error, 1)
			go func() { result <- test.invoke(ctx, cache) }()
			select {
			case <-endpoint.commandStarted:
			case <-time.After(time.Second):
				t.Fatal("blocking Redis command never reached the TCP seam")
			}
			var err error
			select {
			case err = <-result:
			case <-time.After(time.Second):
				t.Fatal("cache command did not return after context termination")
			}
			if !errors.Is(err, test.wantError) {
				t.Fatalf("cache command error = %v, want %v", err, test.wantError)
			}
			select {
			case <-processDone:
			default:
				t.Fatal("cache returned before the underlying v9 command processor ended")
			}
			select {
			case <-endpoint.connectionStopped:
			case <-time.After(time.Second):
				t.Fatal("context termination left a detached Redis command on the socket")
			}
		})
	}
}

func TestRedisMaasCacheCommandRetainsSharedPermitUntilTermination(t *testing.T) {
	endpoint := startBlockingRedisEndpoint(t, "get")
	cache := newRedisMaasCache(&legacyredis.Options{
		Network: "tcp", Addr: endpoint.address, MaxRetries: -1,
		DialTimeout: time.Second, ReadTimeout: -1, WriteTimeout: -1,
		PoolSize: 1, PoolTimeout: time.Second,
	})
	defer cache.Close()
	processDone := make(chan struct{})
	cache.client.AddHook(&commandCompletionHook{target: "get", done: processDone})
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: &maasTDXStore{token: "tok"}, IMSKey: shared.TDXLegacyIMSKey})
	server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: 1, Timeout: 80 * time.Millisecond})
	request := &pb.MaasPlanRequest{FromLat: 25, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6, Date: "2027-01-01", Time: "08:00"}
	firstDone := make(chan error, 1)
	go func() {
		_, err := server.Plan(context.Background(), request)
		firstDone <- err
	}()
	select {
	case <-endpoint.commandStarted:
	case <-time.After(time.Second):
		t.Fatal("shared Redis command never reached the TCP seam")
	}
	other := proto.Clone(request).(*pb.MaasPlanRequest)
	other.ToLat += 0.01
	if _, err := server.Plan(context.Background(), other); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("shared permit released while Redis command was active: code=%v error=%v", status.Code(err), err)
	}
	if err := <-firstDone; status.Code(err) != codes.DeadlineExceeded {
		t.Fatalf("bounded shared Redis work code = %v, want %v (error=%v)", status.Code(err), codes.DeadlineExceeded, err)
	}
	select {
	case <-processDone:
	default:
		t.Fatal("shared flight returned before Redis command termination")
	}
	if got := len(server.workSlots); got != 0 {
		t.Fatalf("shared permit leaked after Redis command termination: %d", got)
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

type cancelAfterRateContext struct {
	context.Context
	errCalls atomic.Int32
}

func (c *cancelAfterRateContext) Err() error {
	if c.errCalls.Add(1) >= 2 {
		return context.Canceled
	}
	return nil
}

func TestMaasResourceInterceptorChecksCancellationBeforeAndAfterRateAccounting(t *testing.T) {
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }

	t.Run("already canceled does not consume rate quota", func(t *testing.T) {
		interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
			RateLimit: 1, RateWindow: time.Minute,
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

	t.Run("cancellation immediately after rate accounting skips handler", func(t *testing.T) {
		interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
			RateLimit: 10, RateWindow: time.Minute,
		})
		ctx := &cancelAfterRateContext{Context: limiterContext("203.0.113.41:1234")}
		called := false
		_, err := interceptor(ctx, nil, info, func(context.Context, interface{}) (interface{}, error) {
			called = true
			return "unexpected", nil
		})
		if status.Code(err) != codes.Canceled || called {
			t.Fatalf("post-rate cancellation = (code=%v called=%v)", status.Code(err), called)
		}
	})
}

func TestMaasSharedFlightSurvivesLeaderCancellationAndOwnsPermit(t *testing.T) {
	upstreamStarted := make(chan struct{})
	releaseUpstream := make(chan struct{})
	var hits, active, peak atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		current := active.Add(1)
		defer active.Add(-1)
		for {
			observed := peak.Load()
			if current <= observed || peak.CompareAndSwap(observed, current) {
				break
			}
		}
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
	cache := newControlledMaasCache()
	server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: 1, Timeout: 2 * time.Second})
	server.maasClient.SetBaseURL(upstream.URL).SetRetryCount(0)
	interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
		RateLimit: 100, RateWindow: time.Minute,
	})
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	req := &pb.MaasPlanRequest{FromLat: 25.0, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6, Date: "2027-01-01", Time: "08:00"}
	planHandler := func(ctx context.Context, request interface{}) (interface{}, error) {
		return server.Plan(ctx, request.(*pb.MaasPlanRequest))
	}

	leaderCtx, cancelLeader := context.WithCancel(limiterContext("203.0.113.50:1234"))
	leaderDone := make(chan error, 1)
	go func() {
		_, err := interceptor(leaderCtx, req, info, planHandler)
		leaderDone <- err
	}()
	<-upstreamStarted

	followerJoined := make(chan struct{})
	followerCtx := &doneObservedContext{
		Context:  limiterContext("203.0.113.51:1234"),
		observed: followerJoined,
	}
	followerDone := make(chan error, 1)
	go func() {
		_, err := interceptor(followerCtx, req, info, planHandler)
		followerDone <- err
	}()
	<-followerJoined
	cancelLeader()

	select {
	case err := <-leaderDone:
		if status.Code(err) != codes.Canceled {
			close(releaseUpstream)
			t.Fatalf("leader code = %v, want %v", status.Code(err), codes.Canceled)
		}
	case <-time.After(250 * time.Millisecond):
		close(releaseUpstream)
		t.Fatal("canceled leader did not return promptly")
	}

	otherReq := proto.Clone(req).(*pb.MaasPlanRequest)
	otherReq.ToLat += 0.01
	if _, err := interceptor(limiterContext("203.0.113.52:1234"), otherReq, info, planHandler); status.Code(err) != codes.ResourceExhausted {
		close(releaseUpstream)
		t.Fatalf("leader cancellation released active shared-work permit: code=%v error=%v", status.Code(err), err)
	}

	select {
	case err := <-followerDone:
		close(releaseUpstream)
		t.Fatalf("follower finished before shared work release: %v", err)
	default:
	}
	close(releaseUpstream)
	if err := <-followerDone; err != nil {
		t.Fatalf("valid follower failed after leader cancellation: %v", err)
	}
	if got := cache.getCalls.Load(); got != 1 {
		t.Fatalf("same-key callers performed %d cache Gets, want one shared Get", got)
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("same-key callers performed %d upstream requests, want one", got)
	}
	if got := peak.Load(); got != 1 {
		t.Fatalf("peak upstream concurrency = %d, want 1", got)
	}

	thirdReq := proto.Clone(req).(*pb.MaasPlanRequest)
	thirdReq.ToLat += 0.02
	if _, err := interceptor(limiterContext("203.0.113.53:1234"), thirdReq, info, planHandler); err != nil {
		t.Fatalf("shared-work permit leaked after completion: %v", err)
	}
	if got := peak.Load(); got != 1 {
		t.Fatalf("shared-work cap was exceeded: peak=%d", got)
	}
}

func TestMaasSharedCacheGetAndSetHonorContexts(t *testing.T) {
	request := &pb.MaasPlanRequest{FromLat: 25.0, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6, Date: "2027-01-01", Time: "08:00"}
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: &maasTDXStore{token: "tok"}, IMSKey: shared.TDXLegacyIMSKey})

	t.Run("caller cancellation returns while shared Get remains bounded", func(t *testing.T) {
		getStarted := make(chan struct{})
		getRelease := make(chan struct{})
		getCtxEnd := make(chan struct{})
		cache := newControlledMaasCache()
		cache.getStart, cache.getBlock, cache.getCtxEnd = getStarted, getRelease, getCtxEnd
		server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: 1, Timeout: 40 * time.Millisecond})
		ctx, cancel := context.WithCancel(context.Background())
		done := make(chan error, 1)
		go func() {
			_, err := server.Plan(ctx, request)
			done <- err
		}()
		<-getStarted
		cancel()
		select {
		case err := <-done:
			if status.Code(err) != codes.Canceled {
				t.Fatalf("cache Get caller cancellation code = %v", status.Code(err))
			}
		case <-time.After(250 * time.Millisecond):
			t.Fatal("caller cancellation stayed blocked in cache Get")
		}
		select {
		case <-getCtxEnd:
		case <-time.After(250 * time.Millisecond):
			t.Fatal("shared cache Get outlived its bounded context")
		}
	})

	t.Run("shared Set timeout returns DeadlineExceeded and releases permit", func(t *testing.T) {
		setStarted := make(chan struct{})
		setRelease := make(chan struct{})
		setCtxEnd := make(chan struct{})
		cache := newControlledMaasCache()
		cache.setStart, cache.setBlock, cache.setCtxEnd = setStarted, setRelease, setCtxEnd
		upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{"result":"success","data":{"routes":[]}}`)
		}))
		defer upstream.Close()
		server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: 1, Timeout: 40 * time.Millisecond})
		server.maasClient.SetBaseURL(upstream.URL).SetRetryCount(0)
		done := make(chan error, 1)
		go func() {
			_, err := server.Plan(context.Background(), request)
			done <- err
		}()
		<-setStarted
		select {
		case <-setCtxEnd:
		case <-time.After(250 * time.Millisecond):
			t.Fatal("cache Set outlived the shared timeout")
		}
		if err := <-done; status.Code(err) != codes.DeadlineExceeded {
			t.Fatalf("cache Set timeout code = %v, want %v (error=%v)", status.Code(err), codes.DeadlineExceeded, err)
		}
		close(setRelease)
		other := proto.Clone(request).(*pb.MaasPlanRequest)
		other.ToLat += 0.01
		if _, err := server.Plan(context.Background(), other); err != nil {
			t.Fatalf("shared-work permit leaked after Set timeout: %v", err)
		}
	})
}

// TestMaasServerCloseJoinsFlightAfterCallerCancels covers the case where the
// RPC caller cancels and Plan returns while the shared singleflight closure
// is still active in a cache/upstream call. Shutdown (Close) must cancel that
// flight's lifecycle context so it unblocks promptly, and must join it before
// returning — otherwise backend cleanup (cache/DB/legacy Redis Close) can run
// concurrently with the still-active flight.
func TestMaasServerCloseJoinsFlightAfterCallerCancels(t *testing.T) {
	getStarted := make(chan struct{})
	getRelease := make(chan struct{}) // deliberately never closed by the test
	getCtxEnd := make(chan struct{})
	cache := newControlledMaasCache()
	cache.getStart, cache.getBlock, cache.getCtxEnd = getStarted, getRelease, getCtxEnd
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: &maasTDXStore{token: "tok"}, IMSKey: shared.TDXLegacyIMSKey})
	server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: 1, Timeout: 5 * time.Second})

	request := &pb.MaasPlanRequest{FromLat: 25, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6, Date: "2027-01-01", Time: "08:00"}
	callerCtx, cancelCaller := context.WithCancel(context.Background())
	planDone := make(chan error, 1)
	go func() {
		_, err := server.Plan(callerCtx, request)
		planDone <- err
	}()
	<-getStarted
	cancelCaller()
	select {
	case err := <-planDone:
		if status.Code(err) != codes.Canceled {
			t.Fatalf("caller cancellation code = %v", status.Code(err))
		}
	case <-time.After(250 * time.Millisecond):
		t.Fatal("caller cancellation did not return promptly")
	}

	// The RPC caller is gone, but the shared flight is still blocked in the
	// cache Get (that is the point of singleflight). Shutdown must cancel and
	// join it before returning.
	closeDone := make(chan struct{})
	go func() {
		server.Close()
		close(closeDone)
	}()
	select {
	case <-getCtxEnd:
	case <-time.After(250 * time.Millisecond):
		t.Fatal("Close did not cancel the active shared flight's lifecycle context")
	}
	select {
	case <-closeDone:
	case <-time.After(250 * time.Millisecond):
		t.Fatal("Close did not join the shared flight before returning")
	}
}

// TestMaasServerCloseVersusPlanRaceLeavesNoLeakedPermitOrCacheCommand races
// concurrent Plan calls against Close. Every call must either complete
// normally (it started registering before Close observed it) or fail
// immediately with the closing sentinel (it observed Close first) — starting
// a new singleflight closure must never race Close's wait. No shared-work
// permit may leak, and calls made after Close returns must never reach the
// cache.
func TestMaasServerCloseVersusPlanRaceLeavesNoLeakedPermitOrCacheCommand(t *testing.T) {
	cache := newControlledMaasCache()
	tdx := shared.NewTDXClient(shared.TDXConfig{Store: &maasTDXStore{token: "tok"}, IMSKey: shared.TDXLegacyIMSKey})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"result":"success","data":{"routes":[]}}`)
	}))
	defer upstream.Close()
	// MaxConcurrent covers every attempt so the shared-work permit never runs
	// out; the only rejection this test exercises is the closing gate.
	const attempts = 50
	server := newMaasServerWithCache(cache, nil, tdx, maasSharedWorkConfig{MaxConcurrent: attempts, Timeout: time.Second})
	server.maasClient.SetBaseURL(upstream.URL).SetRetryCount(0)

	var wg sync.WaitGroup
	errs := make([]error, attempts)
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			req := &pb.MaasPlanRequest{
				FromLat: 25, FromLon: 121.5, ToLat: 25.1, ToLon: 121.6 + float64(i)*0.001,
				Date: "2027-01-01", Time: "08:00",
			}
			_, errs[i] = server.Plan(context.Background(), req)
		}(i)
	}
	server.Close()
	wg.Wait()

	for i, err := range errs {
		code := status.Code(err)
		if err != nil && code != codes.Unavailable && code != codes.Canceled && code != codes.DeadlineExceeded {
			t.Fatalf("attempt %d unexpected error: %v", i, err)
		}
	}
	if got := len(server.workSlots); got != 0 {
		t.Fatalf("shared-work permit leaked after Close/Plan race: %d", got)
	}

	getCallsAfterRace := cache.getCalls.Load()
	postCloseReq := &pb.MaasPlanRequest{FromLat: 1, FromLon: 1, ToLat: 2, ToLon: 2, Date: "2027-01-01", Time: "08:00"}
	if _, err := server.Plan(context.Background(), postCloseReq); status.Code(err) != codes.Unavailable {
		t.Fatalf("post-close Plan code = %v, want %v", status.Code(err), codes.Unavailable)
	}
	if got := cache.getCalls.Load(); got != getCallsAfterRace {
		t.Fatalf("post-close Plan reached the cache: calls %d -> %d", getCallsAfterRace, got)
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
