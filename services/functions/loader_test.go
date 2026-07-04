package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

// fakeLoadSource serves fixed JSON per (table,partVal) and a fixed fetched_at.
// It is the loadSource seam's in-memory adapter for unit tests.
type fakeLoadSource struct {
	json    map[string][]byte // key: table + "|" + partVal
	fetched time.Time
	calls   []string
}

func (f *fakeLoadSource) datasetJSON(_ context.Context, table, _, partVal string) ([]byte, time.Time, error) {
	f.calls = append(f.calls, table+"|"+partVal)
	b, ok := f.json[table+"|"+partVal]
	if !ok {
		return []byte("[]"), f.fetched, nil
	}
	return b, f.fetched, nil
}

func TestStalenessCheckSkips(t *testing.T) {
	// A partition older than the 27h threshold must be skipped, not loaded.
	if !isStale(time.Now().Add(-28 * time.Hour)) {
		t.Fatal("28h old partition should be stale")
	}
	if isStale(time.Now().Add(-1 * time.Hour)) {
		t.Fatal("1h old partition should be fresh")
	}
}

func TestRunLoadIteratesPartitionsAndDecodes(t *testing.T) {
	// A registry spec with two partitions must invoke datasetJSON once per
	// partition and hand each a decoder positioned at the array.
	src := &fakeLoadSource{
		json: map[string][]byte{
			"probe|A": []byte(`[{"x":1}]`),
			"probe|B": []byte(`[{"x":2},{"x":3}]`),
		},
		fetched: time.Now(),
	}
	var seen []int
	spec := loadSpec{
		key: "probe", table: "probe", partCol: "city",
		partitions: func() []string { return []string{"A", "B"} },
		load: func(_ context.Context, dec *json.Decoder, _ *pgxpool.Pool, _ *redis.Client, _ string) error {
			if _, err := dec.Token(); err != nil { // opening '['
				return err
			}
			for dec.More() {
				var m struct {
					X int `json:"x"`
				}
				if err := dec.Decode(&m); err != nil {
					return err
				}
				seen = append(seen, m.X)
			}
			return nil
		},
	}
	if err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec}); err != nil {
		t.Fatalf("runLoadSpecs: %v", err)
	}
	if len(seen) != 3 || seen[0] != 1 || seen[1] != 2 || seen[2] != 3 {
		t.Fatalf("decoded values = %v, want [1 2 3]", seen)
	}
	if len(src.calls) != 2 || src.calls[0] != "probe|A" || src.calls[1] != "probe|B" {
		t.Fatalf("datasetJSON calls = %v", src.calls)
	}
}

func TestRunLoadSkipsStalePartition(t *testing.T) {
	src := &fakeLoadSource{
		json:    map[string][]byte{"probe|A": []byte(`[{"x":1}]`)},
		fetched: time.Now().Add(-40 * time.Hour), // stale
	}
	loaded := false
	spec := loadSpec{
		key: "probe", table: "probe", partCol: "city",
		partitions: func() []string { return []string{"A"} },
		load: func(_ context.Context, _ *json.Decoder, _ *pgxpool.Pool, _ *redis.Client, _ string) error {
			loaded = true
			return nil
		},
	}
	if err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec}); err != nil {
		t.Fatalf("runLoadSpecs: %v", err)
	}
	if loaded {
		t.Fatal("stale partition must be skipped, load ran anyway")
	}
}

func TestLoaderRegistryKeysUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, s := range loaderRegistry(nil) {
		if seen[s.key] {
			t.Fatalf("duplicate registry key %q", s.key)
		}
		seen[s.key] = true
	}
}

// TestLoadBusDailyTimetableWritesRedis feeds a daily-timetable array to the
// shared assembly function and asserts it lands the reconstructed protobuf under
// bus_daily_timetable:<subRouteUID> with the expected TTL, exercising the loader
// path that closes the legacy busDailyroute Redis gap. It needs a local Redis
// (127.0.0.1:6379) and skips when one is not reachable, mirroring the DB-gated
// tests' skip posture.
func TestLoadBusDailyTimetableWritesRedis(t *testing.T) {
	rc := redis.NewClient(&redis.Options{
		Addr:        "127.0.0.1:6379",
		DialTimeout: 200 * time.Millisecond,
		MaxRetries:  0,
	})
	defer rc.Close()
	if err := rc.Ping().Err(); err != nil {
		t.Skipf("local Redis not reachable; skipping: %v", err)
	}

	const uid = "ZZ_DTT_SUB1"
	key := "bus_daily_timetable:" + uid
	_ = rc.Del(key).Err()
	defer func() { _ = rc.Del(key).Err() }()

	body := []byte(`[{"SubRouteUID":"` + uid + `","Direction":0,"Timetables":[{"TripID":"T1","IsLowFloor":true,"StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`)
	dec := json.NewDecoder(bytes.NewReader(body))
	if err := loadBusDailyTimetable(context.Background(), dec, nil, rc, "Kaohsiung"); err != nil {
		t.Fatalf("loadBusDailyTimetable: %v", err)
	}

	pb, err := rc.Get(key).Bytes()
	if err != nil {
		t.Fatalf("read %s: %v", key, err)
	}
	var got models.Bus_DailyTimetables
	if err := proto.Unmarshal(pb, &got); err != nil {
		t.Fatalf("unmarshal proto: %v", err)
	}
	if got.SubRouteUID != uid {
		t.Fatalf("SubRouteUID = %q, want %q", got.SubRouteUID, uid)
	}
	dir0, ok := got.Direction[0]
	if !ok || len(dir0.DailyTimetables) != 1 {
		t.Fatalf("direction 0 timetables = %+v, want one entry", got.Direction)
	}
	if dir0.DailyTimetables[0].TripID != "T1" || len(dir0.DailyTimetables[0].StopTimes) != 1 {
		t.Fatalf("assembled trip = %+v, want TripID T1 with one stop", dir0.DailyTimetables[0])
	}
	ttl := rc.TTL(key).Val()
	if ttl <= 23*time.Hour || ttl > 23*time.Hour+30*time.Minute {
		t.Fatalf("TTL = %s, want ~23h30m", ttl)
	}
}

var _ = errors.Is // keep errors imported if unused after edits
