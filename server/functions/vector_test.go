package main

import (
	"strings"
	"testing"
)

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
