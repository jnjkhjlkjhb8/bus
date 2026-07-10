package main

import (
	"context"
	"errors"
	"testing"
)

type fakeNearbyStore struct {
	rows map[nearbyMode][]nearbyCandidate
	err  map[nearbyMode]error
}

func (f fakeNearbyStore) Find(_ context.Context, mode nearbyMode, _ nearbyQuery) ([]nearbyCandidate, error) {
	return f.rows[mode], f.err[mode]
}

type fakeWalkingRouter struct {
	metrics []walkingMetric
	err     error
	calls   int
}

func (f *fakeWalkingRouter) RouteMany(_ context.Context, _ geoPoint, _ []geoPoint) ([]walkingMetric, error) {
	f.calls++
	return f.metrics, f.err
}

func candidate(mode nearbyMode, id, name string, distance float64) nearbyCandidate {
	return nearbyCandidate{
		Mode: mode, ID: id, Name: name, City: "Taipei",
		Point: geoPoint{Lon: 121.5, Lat: 25}, GeodesicMeters: distance,
	}
}

func TestNearbyDiscoveryPreservesBusGroupUIDIdentity(t *testing.T) {
	store := fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{
		nearbyBus: {
			candidate(nearbyBus, "G-1", "台北車站", 80),
			candidate(nearbyBus, "G-2", "台北車站", 90),
		},
	}, err: map[nearbyMode]error{}}
	router := &fakeWalkingRouter{err: errors.New("osrm unavailable")}

	got, err := newNearbyDiscovery(store, router).Discover(context.Background(), nearbyQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.NearBusStations) != 2 {
		t.Fatalf("bus groups = %v, want distinct G-1 and G-2", got.NearBusStations)
	}
	for _, id := range []string{"G-1", "G-2"} {
		group, ok := got.NearBusStations[id]
		if !ok || len(group.NearStations) != 1 || group.NearStations[0].StationID != id {
			t.Fatalf("group %s = %+v, want group_uid as map key and station ID", id, group)
		}
	}
}

func TestNearbyDiscoveryReturnsPartialResponseWhenOneModeFails(t *testing.T) {
	store := fakeNearbyStore{
		rows: map[nearbyMode][]nearbyCandidate{nearbyBike: {candidate(nearbyBike, "B-1", "Bike", 160)}},
		err:  map[nearbyMode]error{nearbyBus: errors.New("bus query failed")},
	}

	got, err := newNearbyDiscovery(store, &fakeWalkingRouter{err: errors.New("osrm unavailable")}).Discover(context.Background(), nearbyQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.NearBikeStations) != 1 || got.NearBikeStations[0].StationID != "B-1" {
		t.Fatalf("bike stations = %+v, want partial success", got.NearBikeStations)
	}
}

func TestNearbyDiscoveryReturnsUnavailableWhenEveryModeFails(t *testing.T) {
	failures := map[nearbyMode]error{}
	for _, mode := range allNearbyModes {
		failures[mode] = errors.New("query failed")
	}

	_, err := newNearbyDiscovery(fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{}, err: failures}, &fakeWalkingRouter{}).
		Discover(context.Background(), nearbyQuery{})
	if !errors.Is(err, ErrNearbyUnavailable) {
		t.Fatalf("err = %v, want ErrNearbyUnavailable", err)
	}
}

func TestNearbyDiscoveryFallsBackWhenRoutingFails(t *testing.T) {
	store := fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{
		nearbyTRA: {candidate(nearbyTRA, "T-1", "TRA", 800)},
	}, err: map[nearbyMode]error{}}

	got, err := newNearbyDiscovery(store, &fakeWalkingRouter{err: errors.New("osrm unavailable")}).Discover(context.Background(), nearbyQuery{})
	if err != nil {
		t.Fatal(err)
	}
	station := got.NearTraStations[0]
	if station.Walk != 10 || station.Distance != 800 || station.Routed {
		t.Fatalf("station = %+v, want geodesic fallback", station)
	}
}

func TestNearbyDiscoverySkipsRoutingForEmptyCandidates(t *testing.T) {
	router := &fakeWalkingRouter{}
	_, err := newNearbyDiscovery(fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{}, err: map[nearbyMode]error{}}, router).
		Discover(context.Background(), nearbyQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if router.calls != 0 {
		t.Fatalf("routing calls = %d, want 0", router.calls)
	}
}

func TestNearbyDiscoveryPropagatesContextCancellation(t *testing.T) {
	store := fakeNearbyStore{rows: map[nearbyMode][]nearbyCandidate{
		nearbyMRT: {candidate(nearbyMRT, "M-1", "MRT", 80)},
	}, err: map[nearbyMode]error{}}

	_, err := newNearbyDiscovery(store, &fakeWalkingRouter{err: context.Canceled}).Discover(context.Background(), nearbyQuery{})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
}
