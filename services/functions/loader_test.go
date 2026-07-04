package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
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

var _ = errors.Is // keep errors imported if unused after edits
