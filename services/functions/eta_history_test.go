package main

import (
	"math"
	"testing"
)

func TestHaversine(t *testing.T) {
	d := haversine(35.6762, 139.6503, 34.6937, 135.5023)
	if d < 350000 || d > 450000 {
		t.Errorf("expected ~400km Tokyo-Osaka, got %f", d)
	}
	if haversine(25.0, 121.5, 25.0, 121.5) != 0 {
		t.Error("same point should be 0")
	}
	_ = math.Pi
}
