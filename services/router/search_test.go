package main

import "testing"

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
