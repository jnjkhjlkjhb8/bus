package main

import "testing"

func TestGridPrecipitation(t *testing.T) {
	vals := make([]float64, 10*10)
	for i := range vals {
		vals[i] = -99
	}
	vals[3*10+2] = 5.5
	p := gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 118.2, 20.3)
	if p == nil {
		t.Fatal("expected value, got nil")
	}
	if *p != 5.5 {
		t.Errorf("expected 5.5, got %f", *p)
	}
	p2 := gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 118.0, 20.0)
	if p2 != nil {
		t.Errorf("expected nil for -99 cell, got %f", *p2)
	}
}

func TestGridPrecipitationBoundary(t *testing.T) {
	vals := make([]float64, 10*10)
	for i := range vals {
		vals[i] = 1.0
	}

	p := gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 117.9, 20.3)
	if p != nil {
		t.Errorf("expected nil for negative x, got %f", *p)
	}

	p = gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 118.2, 19.9)
	if p != nil {
		t.Errorf("expected nil for negative y, got %f", *p)
	}

	p = gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 119.1, 20.3)
	if p != nil {
		t.Errorf("expected nil for x >= dimX, got %f", *p)
	}

	p = gridPrecipitation(vals, 10, 118.0, 20.0, 0.1, 118.9, 21.0)
	if p != nil {
		t.Errorf("expected nil for index overflow, got %f", *p)
	}
}
