package main

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"
)

type fakeNearbyStore struct {
	rows map[nearbyMode][]nearbyCandidate
	err  map[nearbyMode]error
}

type failFastNearbyStore struct {
	blockedStarted  chan struct{}
	blockedCanceled chan struct{}
	release         chan struct{}
}

func (f *failFastNearbyStore) Find(ctx context.Context, mode nearbyMode, _ nearbyQuery) ([]nearbyCandidate, error) {
	switch mode {
	case nearbyBike:
		close(f.blockedStarted)
		select {
		case <-ctx.Done():
			close(f.blockedCanceled)
			return nil, ctx.Err()
		case <-f.release:
			return nil, errors.New("test released blocked query")
		}
	case nearbyBus:
		<-f.blockedStarted
		return nil, errors.New("bus query failed")
	default:
		return nil, nil
	}
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

func TestValidateNearbyQuery(t *testing.T) {
	tests := []struct {
		name       string
		query      nearbyQuery
		wantRadius int
		wantErr    bool
	}{
		{
			name:       "zero radius uses default",
			query:      nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: 25}},
			wantRadius: defaultNearbyRadius,
		},
		{
			name:       "minimum positive radius",
			query:      nearbyQuery{Origin: geoPoint{Lon: -180, Lat: -90}, RadiusMeters: 1},
			wantRadius: 1,
		},
		{
			name:       "maximum radius",
			query:      nearbyQuery{Origin: geoPoint{Lon: 180, Lat: 90}, RadiusMeters: maxNearbyRadius},
			wantRadius: maxNearbyRadius,
		},
		{
			name:    "negative radius",
			query:   nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: 25}, RadiusMeters: -1},
			wantErr: true,
		},
		{
			name:    "radius above maximum",
			query:   nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: 25}, RadiusMeters: 5001},
			wantErr: true,
		},
		{
			name:    "longitude below range",
			query:   nearbyQuery{Origin: geoPoint{Lon: -180.1, Lat: 25}, RadiusMeters: 500},
			wantErr: true,
		},
		{
			name:    "longitude above range",
			query:   nearbyQuery{Origin: geoPoint{Lon: 180.1, Lat: 25}, RadiusMeters: 500},
			wantErr: true,
		},
		{
			name:    "latitude below range",
			query:   nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: -90.1}, RadiusMeters: 500},
			wantErr: true,
		},
		{
			name:    "latitude above range",
			query:   nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: 90.1}, RadiusMeters: 500},
			wantErr: true,
		},
		{
			name:    "non-finite longitude",
			query:   nearbyQuery{Origin: geoPoint{Lon: math.NaN(), Lat: 25}, RadiusMeters: 500},
			wantErr: true,
		},
		{
			name:    "non-finite latitude",
			query:   nearbyQuery{Origin: geoPoint{Lon: 121.5, Lat: math.Inf(1)}, RadiusMeters: 500},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := validateNearbyQuery(tt.query)
			if tt.wantErr {
				if !errors.Is(err, ErrInvalidNearbyQuery) {
					t.Fatalf("err = %v, want ErrInvalidNearbyQuery", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got.RadiusMeters != tt.wantRadius {
				t.Fatalf("radius = %d, want %d", got.RadiusMeters, tt.wantRadius)
			}
		})
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

func TestNearbyDiscoveryRejectsPartialResponseWhenOneModeFails(t *testing.T) {
	store := fakeNearbyStore{
		rows: map[nearbyMode][]nearbyCandidate{nearbyBike: {candidate(nearbyBike, "B-1", "Bike", 160)}},
		err:  map[nearbyMode]error{nearbyBus: errors.New("bus query failed")},
	}

	got, err := newNearbyDiscovery(store, &fakeWalkingRouter{err: errors.New("osrm unavailable")}).Discover(context.Background(), nearbyQuery{})
	if !errors.Is(err, ErrNearbyUnavailable) {
		t.Fatalf("err = %v, want ErrNearbyUnavailable", err)
	}
	if got != nil {
		t.Fatalf("response = %+v, want nil to prevent partial results", got)
	}
}

func TestNearbyDiscoveryFailsFastAndCancelsSiblingQueries(t *testing.T) {
	store := &failFastNearbyStore{
		blockedStarted:  make(chan struct{}),
		blockedCanceled: make(chan struct{}),
		release:         make(chan struct{}),
	}
	t.Cleanup(func() { close(store.release) })

	result := make(chan error, 1)
	go func() {
		response, err := newNearbyDiscovery(store, nil).Discover(context.Background(), nearbyQuery{})
		if response != nil {
			result <- errors.New("discovery returned a partial response")
			return
		}
		result <- err
	}()

	select {
	case err := <-result:
		if !errors.Is(err, ErrNearbyUnavailable) {
			t.Fatalf("err = %v, want ErrNearbyUnavailable", err)
		}
	case <-time.After(time.Second):
		t.Fatal("discovery did not fail promptly")
	}

	select {
	case <-store.blockedCanceled:
	case <-time.After(time.Second):
		t.Fatal("blocked sibling query did not observe cancellation")
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
