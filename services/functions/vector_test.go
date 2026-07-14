package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/pashagolub/pgxmock/v4"
)

type stubEmbeddingClient struct {
	embeddings [][]float32
	err        error
	calls      int
}

func (c *stubEmbeddingClient) Embed(_ context.Context, _ []string) ([][]float32, error) {
	c.calls++
	return c.embeddings, c.err
}

type testVectorRedis struct {
	value          string
	getErr         error
	setErr         error
	setValues      []string
	successfulSets int
}

func (r *testVectorRedis) Get(string) *redis.StringCmd {
	return redis.NewStringResult(r.value, r.getErr)
}

func (r *testVectorRedis) Set(_ string, value interface{}, _ time.Duration) *redis.StatusCmd {
	r.setValues = append(r.setValues, fmt.Sprint(value))
	if r.setErr == nil {
		r.successfulSets++
	}
	return redis.NewStatusResult("OK", r.setErr)
}

type captureTimeArgs struct {
	values []time.Time
}

type roundTripperFunc func(*http.Request) (*http.Response, error)

func (f roundTripperFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

type trackingReadCloser struct {
	io.Reader
	closed bool
}

func (b *trackingReadCloser) Close() error {
	b.closed = true
	return nil
}

func (c *captureTimeArgs) Match(value interface{}) bool {
	cutoff, ok := value.(time.Time)
	if ok {
		c.values = append(c.values, cutoff)
	}
	return ok
}

func newVectorDBMock(t *testing.T) pgxmock.PgxPoolIface {
	t.Helper()
	db, err := pgxmock.NewPool(pgxmock.QueryMatcherOption(pgxmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("pgxmock.NewPool: %v", err)
	}
	t.Cleanup(db.Close)
	return db
}

func expectEmptyVectorQueries(db pgxmock.PgxPoolIface, lower string, cutoff pgxmock.Argument) {
	for _, dataset := range vectorDatasets {
		if dataset.prepareSQL != "" {
			db.ExpectExec(dataset.prepareSQL).
				WillReturnResult(pgxmock.NewResult("DELETE", 0))
		}
		db.ExpectQuery(dataset.query).
			WithArgs(lower, cutoff).
			WillReturnRows(db.NewRows([]string{"unused"}))
	}
}

func vectorDatasetByType(t *testing.T, vectorType string) vectorDataset {
	t.Helper()
	for _, dataset := range vectorDatasets {
		if dataset.vectorType == vectorType {
			return dataset
		}
	}
	t.Fatalf("vector dataset %q not found", vectorType)
	return vectorDataset{}
}

func validBusVectorRows(db pgxmock.PgxPoolIface) *pgxmock.Rows {
	return db.NewRows([]string{"sub_route_uid", "sub_route_name", "city", "depart", "destin"}).
		AddRow("R1", "藍線", "Taipei", "台北車站", "市政府")
}

func TestVectorRegistryIncludesAllSixDatasetsExactlyOnce(t *testing.T) {
	want := map[string]int{
		"bus_route":    1,
		"bus_station":  1,
		"bike_station": 1,
		"mrt_station":  1,
		"tra_station":  1,
		"thsr_station": 1,
	}
	got := make(map[string]int, len(want))
	for _, dataset := range vectorDatasets {
		got[dataset.vectorType]++
	}
	for vectorType, wantCount := range want {
		if got[vectorType] != wantCount {
			t.Errorf("vector type %q occurs %d times, want %d", vectorType, got[vectorType], wantCount)
		}
	}
	if len(vectorDatasets) != len(want) {
		t.Errorf("registry contains %d datasets, want %d", len(vectorDatasets), len(want))
	}
}

func TestVectorRegistryUsesCorrectMRTLabels(t *testing.T) {
	for code, want := range map[string]string{
		"KLRT": "高雄輕軌",
		"TYMC": "桃園捷運",
	} {
		if got := mrtSystemName(code); got != want {
			t.Errorf("mrtSystemName(%q) = %q, want %q", code, got, want)
		}
	}
	if _, ok := mrtSystemNames["NTMC"]; !ok {
		t.Error("mrtSystemNames is missing NTMC")
	}
}

func TestMRTVectorQueryBackfillsLegacyRevisionBeforeLowerWatermark(t *testing.T) {
	for _, want := range []string{
		"ms.updated_at >= $1",
		"ms.updated_at < $2",
		"OR NOT EXISTS",
		"sv.city = CASE ms.system",
		"sv.depart = ms.system",
	} {
		if !strings.Contains(mrtStationsForVectorSQL, want) {
			t.Errorf("MRT vector query missing %q: %s", want, mrtStationsForVectorSQL)
		}
	}
}

func TestMRTLegacyLabelsAreInvalidatedBackfilledAndReembedded(t *testing.T) {
	dataset := vectorDatasetByType(t, "mrt_station")
	if dataset.prepareSQL == "" {
		t.Fatal("MRT vector dataset has no legacy-label invalidation")
	}
	for _, want := range []string{
		"DELETE FROM search_vector",
		"'KLRT'", "'桃園捷運'",
		"'TYMC'", "'台中捷運'",
		"'NTMC'", "'NTMC'",
		"keeper_ms.station_id = stale_sv.uid",
		"CASE keeper_ms.system",
		"= stale_sv.city",
	} {
		if !strings.Contains(dataset.prepareSQL, want) {
			t.Errorf("MRT prepare SQL missing %q: %s", want, dataset.prepareSQL)
		}
	}

	db := newVectorDBMock(t)
	const lower = "2026-07-14T00:00:00Z"
	upper := time.Date(2026, 7, 14, 1, 0, 0, 0, time.UTC)
	db.ExpectExec(dataset.prepareSQL).
		WillReturnResult(pgxmock.NewResult("DELETE", 2))
	db.ExpectQuery(dataset.query).
		WithArgs(lower, upper).
		WillReturnRows(db.NewRows([]string{"station_id", "name", "system", "geom"}).
			AddRow("shared", "輕軌轉乘站", "KLRT", "POINT(120 22)").
			AddRow("shared", "機捷轉乘站", "TYMC", "POINT(121 25)").
			AddRow("N01", "新北產業園區", "NTMC", "POINT(121.4 25.1)"))
	embedder := &stubEmbeddingClient{embeddings: [][]float32{
		make([]float32, embeddingDimension),
		make([]float32, embeddingDimension),
		make([]float32, embeddingDimension),
	}}
	batch := db.ExpectBatch()
	batch.ExpectExec(searchVectorUpsertSQL).
		WithArgs("mrt_station", "shared", "輕軌轉乘站", "高雄輕軌", "KLRT", "", "POINT(120 22)", pgxmock.AnyArg()).
		WillReturnResult(pgxmock.NewResult("INSERT", 1))
	batch.ExpectExec(searchVectorUpsertSQL).
		WithArgs("mrt_station", "shared", "機捷轉乘站", "桃園捷運", "TYMC", "", "POINT(121 25)", pgxmock.AnyArg()).
		WillReturnResult(pgxmock.NewResult("INSERT", 1))
	batch.ExpectExec(searchVectorUpsertSQL).
		WithArgs("mrt_station", "N01", "新北產業園區", "新北捷運", "NTMC", "", "POINT(121.4 25.1)", pgxmock.AnyArg()).
		WillReturnResult(pgxmock.NewResult("INSERT", 1))

	if err := processVectorDataset(context.Background(), db, embedder, dataset, lower, upper); err != nil {
		t.Fatalf("processVectorDataset() error = %v", err)
	}
	if embedder.calls != 1 {
		t.Fatalf("Embed() calls = %d, want 1 backfill batch", embedder.calls)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatalf("database expectations: %v", err)
	}
}

func TestProcessVectorBatchRejectsTooManyEmbeddings(t *testing.T) {
	embedder := &stubEmbeddingClient{embeddings: [][]float32{
		make([]float32, 1024),
		make([]float32, 1024),
	}}
	err := processVectorBatch(context.Background(), nil, embedder,
		[]string{"one"}, []resp{{UID: "1"}})
	if err == nil || !strings.Contains(err.Error(), "embedding count") {
		t.Fatalf("processVectorBatch() error = %v, want embedding count error", err)
	}
}

func TestProcessVectorBatchRejectsTooFewEmbeddings(t *testing.T) {
	embedder := &stubEmbeddingClient{embeddings: [][]float32{
		make([]float32, 1024),
	}}
	err := processVectorBatch(context.Background(), nil, embedder,
		[]string{"one", "two"}, []resp{{UID: "1"}, {UID: "2"}})
	if err == nil || !strings.Contains(err.Error(), "embedding count") {
		t.Fatalf("processVectorBatch() error = %v, want embedding count error", err)
	}
}

func TestProcessVectorBatchRejectsWrongDimension(t *testing.T) {
	embedder := &stubEmbeddingClient{embeddings: [][]float32{
		make([]float32, 1023),
	}}
	err := processVectorBatch(context.Background(), nil, embedder,
		[]string{"one"}, []resp{{UID: "1"}})
	if err == nil || !strings.Contains(err.Error(), "dimension") {
		t.Fatalf("processVectorBatch() error = %v, want dimension error", err)
	}
}

func TestChangeToVectorCapturesCutoffBeforeFirstQuery(t *testing.T) {
	const lower = "2026-07-13T00:00:00Z"
	db := newVectorDBMock(t)
	cutoffs := &captureTimeArgs{}
	expectEmptyVectorQueries(db, lower, cutoffs)
	cache := &testVectorRedis{value: lower}
	embedder := &stubEmbeddingClient{}

	if err := changeToVector(context.Background(), cache, db, embedder); err != nil {
		t.Fatalf("changeToVector() error = %v", err)
	}
	if len(cutoffs.values) != len(vectorDatasets) {
		t.Fatalf("captured %d cutoffs, want %d", len(cutoffs.values), len(vectorDatasets))
	}
	for i, got := range cutoffs.values[1:] {
		if !got.Equal(cutoffs.values[0]) {
			t.Errorf("query %d cutoff = %s, first query cutoff = %s", i+2, got, cutoffs.values[0])
		}
	}
	wantWatermark := cutoffs.values[0].Format(time.RFC3339Nano)
	if len(cache.setValues) != 1 || cache.setValues[0] != wantWatermark {
		t.Fatalf("watermark writes = %v, want [%s]", cache.setValues, wantWatermark)
	}
	if embedder.calls != 0 {
		t.Fatalf("Embed() calls = %d, want 0 for empty datasets", embedder.calls)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatalf("database expectations: %v", err)
	}
}

func TestChangeToVectorDoesNotAdvanceWatermarkOnAnyFailure(t *testing.T) {
	const lower = "2026-07-13T00:00:00Z"
	wantErr := errors.New("vector dependency failed")
	for _, failure := range []string{
		"redis get",
		"query",
		"prepare",
		"scan",
		"rows",
		"embed",
		"batch",
		"redis set",
	} {
		t.Run(failure, func(t *testing.T) {
			db := newVectorDBMock(t)
			cache := &testVectorRedis{value: lower}
			embedder := &stubEmbeddingClient{}
			switch failure {
			case "redis get":
				cache.getErr = wantErr
			case "query":
				db.ExpectQuery(vectorDatasets[0].query).
					WithArgs(lower, pgxmock.AnyArg()).
					WillReturnError(wantErr)
			case "prepare":
				for _, dataset := range vectorDatasets {
					if dataset.prepareSQL != "" {
						db.ExpectExec(dataset.prepareSQL).WillReturnError(wantErr)
						break
					}
					db.ExpectQuery(dataset.query).
						WithArgs(lower, pgxmock.AnyArg()).
						WillReturnRows(db.NewRows([]string{"unused"}))
				}
			case "scan":
				db.ExpectQuery(vectorDatasets[0].query).
					WithArgs(lower, pgxmock.AnyArg()).
					WillReturnRows(db.NewRows([]string{"sub_route_uid"}).AddRow("R1"))
			case "rows":
				db.ExpectQuery(vectorDatasets[0].query).
					WithArgs(lower, pgxmock.AnyArg()).
					WillReturnRows(validBusVectorRows(db).RowError(0, wantErr))
			case "embed":
				db.ExpectQuery(vectorDatasets[0].query).
					WithArgs(lower, pgxmock.AnyArg()).
					WillReturnRows(validBusVectorRows(db))
				embedder.err = wantErr
			case "batch":
				db.ExpectQuery(vectorDatasets[0].query).
					WithArgs(lower, pgxmock.AnyArg()).
					WillReturnRows(validBusVectorRows(db))
				embedder.embeddings = [][]float32{make([]float32, 1024)}
				batch := db.ExpectBatch()
				batch.ExpectExec(searchVectorUpsertSQL).
					WithArgs(
						pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg(),
						pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg(),
					).
					WillReturnError(wantErr)
			case "redis set":
				expectEmptyVectorQueries(db, lower, pgxmock.AnyArg())
				cache.setErr = wantErr
			}

			err := changeToVector(context.Background(), cache, db, embedder)
			if err == nil {
				t.Fatal("changeToVector() error = nil, want failure")
			}
			if failure == "scan" {
				if !strings.Contains(err.Error(), "scan") {
					t.Fatalf("changeToVector() error = %v, want scan error", err)
				}
			} else if !errors.Is(err, wantErr) {
				t.Fatalf("changeToVector() error = %v, want wrapped %v", err, wantErr)
			}
			if cache.successfulSets != 0 {
				t.Fatalf("successful watermark writes = %d, want 0", cache.successfulSets)
			}
			if err := db.ExpectationsWereMet(); err != nil {
				t.Fatalf("database expectations: %v", err)
			}
		})
	}
}

func TestHTTPEmbedderHonorsContextTimeoutAndHTTPStatus(t *testing.T) {
	t.Run("context timeout", func(t *testing.T) {
		release := make(chan struct{})
		server := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, request *http.Request) {
			select {
			case <-request.Context().Done():
			case <-release:
			}
		}))
		defer server.Close()
		defer close(release)
		embedder := newHTTPEmbedder(server.URL)
		if timeout := embedder.client.GetClient().Timeout; timeout <= 0 {
			t.Fatalf("HTTP client timeout = %s, want finite timeout", timeout)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		defer cancel()
		_, err := embedder.Embed(ctx, []string{"台北車站"})
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("Embed() error = %v, want context deadline exceeded", err)
		}
	})

	t.Run("HTTP status", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
			response.WriteHeader(http.StatusServiceUnavailable)
			_, _ = response.Write([]byte(`{"embeddings":[]}`))
		}))
		defer server.Close()
		_, err := newHTTPEmbedder(server.URL).Embed(context.Background(), []string{"台北車站"})
		if err == nil || !strings.Contains(err.Error(), "503") {
			t.Fatalf("Embed() error = %v, want HTTP 503 error", err)
		}
	})

	t.Run("response body close", func(t *testing.T) {
		body := &trackingReadCloser{Reader: strings.NewReader(`{"embeddings":[]}`)}
		embedder := newHTTPEmbedder("http://embed.test/api/embed")
		embedder.client.SetTransport(roundTripperFunc(func(request *http.Request) (*http.Response, error) {
			return &http.Response{
				Status:     "200 OK",
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       body,
				Request:    request,
			}, nil
		}))
		if _, err := embedder.Embed(context.Background(), []string{"台北車站"}); err != nil {
			t.Fatalf("Embed() error = %v", err)
		}
		if !body.closed {
			t.Fatal("Embed() did not close the response body")
		}
	})
}

func TestVectorQueriesSkipFreshEmbeddings(t *testing.T) {
	queries := map[string]string{
		"bus_route":    busSubroutesForVectorSQL,
		"bus_station":  busStationsForVectorSQL,
		"bike_station": bikeStationsForVectorSQL,
		"mrt_station":  mrtStationsForVectorSQL,
		"thsr_station": thsrStationsForVectorSQL,
		"tra_station":  traStationsForVectorSQL,
	}
	for vectorType, query := range queries {
		for _, want := range []string{
			"updated_at >= $1",
			"updated_at < $2",
			"NOT EXISTS",
			"sv.type = '" + vectorType + "'",
			"sv.embedding IS NOT NULL",
		} {
			if !strings.Contains(query, want) {
				t.Fatalf("%s query missing %q", vectorType, want)
			}
		}
		if strings.Contains(query, "sv.updated_at >=") {
			t.Fatalf("%s query still compares updated_at: %s", vectorType, query)
		}
	}
}

func TestFreshVectorSkipSQLComparesContent(t *testing.T) {
	got := freshVectorSkipSQL("bus_route", "bs.sub_route_uid", "sv.name = bs.sub_route_name AND sv.depart = bs.depart AND sv.destin = bs.destin")
	if !strings.Contains(got, "sv.name = bs.sub_route_name") {
		t.Fatalf("missing content predicate: %s", got)
	}
	if strings.Contains(got, "sv.updated_at >=") {
		t.Fatalf("still compares updated_at: %s", got)
	}
}

func TestEmbeddingURLUsesEnvAndTrimSpace(t *testing.T) {
	t.Setenv("EMBED_URL", " http://embed:11434/api/embed ")
	if got := embeddingURL(); got != "http://embed:11434/api/embed" {
		t.Fatalf("embeddingURL() = %q", got)
	}
}

func TestEmbeddingURLEmptyDisablesVectorUpdate(t *testing.T) {
	t.Setenv("EMBED_URL", "")
	if got := embeddingURL(); got != "" {
		t.Fatalf("embeddingURL() = %q, want empty", got)
	}
}
