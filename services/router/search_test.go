package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	pgxmock "github.com/pashagolub/pgxmock/v4"
)

type deadlineSearchDB struct {
	t      *testing.T
	called bool
}

func (d *deadlineSearchDB) Query(ctx context.Context, _ string, _ ...any) (pgx.Rows, error) {
	d.t.Helper()
	d.called = true
	deadline, ok := ctx.Deadline()
	if !ok {
		d.t.Fatal("search query context has no deadline")
	}
	if remaining := time.Until(deadline); remaining <= 0 || remaining > searchRequestTimeout {
		d.t.Fatalf("search query deadline remaining = %v, want within %v", remaining, searchRequestTimeout)
	}
	return nil, errors.New("stop after context inspection")
}

func performSearchRequest(t *testing.T, db searchDB, query string) *httptest.ResponseRecorder {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/api/search", handleSearch(db))
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/search?q="+url.QueryEscape(query), nil)
	router.ServeHTTP(recorder, request)
	return recorder
}

func TestHandleSearchLimitsQueryByUnicodeRunes(t *testing.T) {
	t.Setenv("EMBED_URL", "")
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery(`(?s)FROM search_vector.*WHERE uid = \$1`).
		WithArgs(strings.Repeat("界", 128), 20).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}))

	if got := performSearchRequest(t, db, strings.Repeat("界", 128)); got.Code != http.StatusOK {
		t.Fatalf("128-rune status = %d, body = %s, want 200", got.Code, got.Body.String())
	}
	if got := performSearchRequest(t, db, strings.Repeat("界", 129)); got.Code != http.StatusBadRequest {
		t.Fatalf("129-rune status = %d, body = %s, want 400", got.Code, got.Body.String())
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestEmbedQueryHonorsContextCancellation(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		close(started)
		select {
		case <-r.Context().Done():
		case <-release:
		}
	}))
	defer func() {
		close(release)
		upstream.Close()
	}()
	t.Setenv("EMBED_URL", upstream.URL)

	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() {
		_, err := embedQuery(ctx, "台北車站")
		errCh <- err
	}()
	<-started
	cancel()

	select {
	case err := <-errCh:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("err = %v, want context.Canceled", err)
		}
	case <-time.After(time.Second):
		t.Fatal("embed request did not stop after cancellation")
	}
}

func TestEmbedQueryHonorsContextDeadline(t *testing.T) {
	release := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done():
		case <-release:
		}
	}))
	defer func() {
		close(release)
		upstream.Close()
	}()
	t.Setenv("EMBED_URL", upstream.URL)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	_, err := embedQuery(ctx, "台北車站")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want context.DeadlineExceeded", err)
	}
}

func TestHandleSearchBoundsDatabaseQuery(t *testing.T) {
	t.Setenv("EMBED_URL", "")
	db := &deadlineSearchDB{t: t}

	got := performSearchRequest(t, db, "台北")
	if got.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, body = %s, want 500", got.Code, got.Body.String())
	}
	if !db.called {
		t.Fatal("database query was not called")
	}
}

func TestTextSearchReturnsScanError(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery(`(?s)FROM search_vector.*WHERE uid = \$1`).
		WithArgs("台北", 20).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
			AddRow(struct{}{}, "uid", "name", "city", "depart", "destin", nil, nil))

	results, err := textSearch(context.Background(), "台北", 20, db)
	if err == nil {
		t.Fatalf("results = %#v, want scan error", results)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestExpandStationRoutesReturnsRowsErrorWithoutPartialResults(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	wantErr := errors.New("route expansion rows failed")

	db.ExpectQuery(`(?s)FROM bus_station_group_members`).
		WithArgs([]string{"G-1"}).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
			AddRow("bus_route", "R-1", "307", "Taipei", "A", "B", nil, nil).
			CloseError(wantErr))

	results, err := expandStationRoutes(context.Background(), []searchResult{{Type: "bus_station", UID: "G-1"}}, db)
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if results != nil {
		t.Fatalf("results = %#v, want nil to prevent partial results", results)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestHandleSearchFailsOnVectorScanError(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"embeddings":[[1,2]]}`))
	}))
	defer upstream.Close()
	t.Setenv("EMBED_URL", upstream.URL)

	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery(`(?s)FROM search_vector.*WHERE uid = \$1`).
		WithArgs("台北", 20).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}))
	db.ExpectQuery(`(?s)FROM search_vector.*ORDER BY embedding`).
		WithArgs("[1,2]", 20).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
			AddRow(struct{}{}, "uid", "name", "city", "depart", "destin", nil, nil))

	got := performSearchRequest(t, db, "台北")
	if got.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, body = %s, want 500", got.Code, got.Body.String())
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestTrainNumberSearchRejectsPartialRows(t *testing.T) {
	rowsErr := errors.New("train rows failed")
	tests := []struct {
		name string
		rows *pgxmock.Rows
		err  error
	}{
		{
			name: "scan error",
			rows: pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
				AddRow("tra_train", "1234", "1234", "", "A", "B", nil, nil).
				AddRow(struct{}{}, "5678", "5678", "", "A", "B", nil, nil),
		},
		{
			name: "rows error",
			rows: pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
				AddRow("tra_train", "1234", "1234", "", "A", "B", nil, nil).
				CloseError(rowsErr),
			err: rowsErr,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			db, err := pgxmock.NewPool()
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			db.ExpectQuery(`(?s)FROM search_vector.*type IN`).WithArgs("1234").WillReturnRows(tt.rows)

			results, err := trainNumberSearch(context.Background(), "1234", db)
			if err == nil {
				t.Fatalf("results = %#v, want error", results)
			}
			if tt.err != nil && !errors.Is(err, tt.err) {
				t.Fatalf("err = %v, want %v", err, tt.err)
			}
			if results != nil {
				t.Fatalf("results = %#v, want nil to prevent partial results", results)
			}
			if err := db.ExpectationsWereMet(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestHandleSearchFailsWhenRouteExpansionFails(t *testing.T) {
	t.Setenv("EMBED_URL", "")
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	db.ExpectQuery(`(?s)FROM search_vector.*WHERE uid = \$1`).
		WithArgs("台北車站", 20).
		WillReturnRows(pgxmock.NewRows([]string{"type", "uid", "name", "city", "depart", "destin", "lat", "lon"}).
			AddRow("bus_station", "G-1", "台北車站", "Taipei", "", "", nil, nil))
	db.ExpectQuery(`(?s)FROM bus_station_group_members`).
		WithArgs([]string{"G-1"}).
		WillReturnError(errors.New("route expansion failed"))

	got := performSearchRequest(t, db, "台北車站")
	if got.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, body = %s, want 500", got.Code, got.Body.String())
	}
	if strings.Contains(got.Body.String(), "G-1") {
		t.Fatalf("body = %s, must not contain partial station result", got.Body.String())
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestIsNumericQuery(t *testing.T) {
	tests := []struct {
		name string
		q    string
		want bool
	}{
		{name: "empty", q: "", want: false},
		{name: "digits", q: "1234", want: true},
		{name: "route with letter", q: "307A", want: false},
		{name: "station", q: "台北", want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isNumericQuery(tt.q); got != tt.want {
				t.Fatalf("isNumericQuery(%q) = %v, want %v", tt.q, got, tt.want)
			}
		})
	}
}

func TestShouldUseVector(t *testing.T) {
	tests := []struct {
		name string
		q    string
		want bool
	}{
		{name: "one rune", q: "北", want: false},
		{name: "station", q: "台北", want: true},
		{name: "numeric train", q: "1234", want: false},
		{name: "route code", q: "307A", want: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldUseVector(tt.q); got != tt.want {
				t.Fatalf("shouldUseVector(%q) = %v, want %v", tt.q, got, tt.want)
			}
		})
	}
}

func TestEmbeddingURLUsesEnvAndTrimSpace(t *testing.T) {
	t.Setenv("EMBED_URL", " http://embed:11434/api/embed ")
	if got := embeddingURL(); got != "http://embed:11434/api/embed" {
		t.Fatalf("embeddingURL() = %q", got)
	}
}

func TestEmbeddingURLEmptyDisablesVectorSearch(t *testing.T) {
	t.Setenv("EMBED_URL", "")
	if got := embeddingURL(); got != "" {
		t.Fatalf("embeddingURL() = %q, want empty", got)
	}
}

func TestMergeSearchResultsDedupesInPriorityOrder(t *testing.T) {
	train := []searchResult{
		{Type: "tra_train", UID: "1234", Name: "1234"},
	}
	text := []searchResult{
		{Type: "tra_train", UID: "1234", Name: "duplicate"},
		{Type: "bus_route", UID: "R1", Name: "307"},
	}
	vector := []searchResult{
		{Type: "bus_route", UID: "R1", Name: "duplicate route"},
		{Type: "mrt_station", UID: "BL12", Name: "台北車站"},
	}

	got := mergeSearchResults(10, train, text, vector)
	if len(got) != 3 {
		t.Fatalf("len = %d, want 3: %#v", len(got), got)
	}
	if got[0].Name != "1234" || got[1].Name != "307" || got[2].Name != "台北車站" {
		t.Fatalf("unexpected order: %#v", got)
	}
}

func TestMergeSearchResultsHonorsLimit(t *testing.T) {
	got := mergeSearchResults(
		2,
		[]searchResult{
			{Type: "bus_route", UID: "1"},
			{Type: "bus_route", UID: "2"},
		},
		[]searchResult{{Type: "bus_route", UID: "3"}},
	)
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2: %#v", len(got), got)
	}
}
