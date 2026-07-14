package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type busSnapshotSource struct {
	bodies map[string][]byte
	times  map[string]time.Time
	cycles map[string]string
	errors map[string]error
	calls  []string
}

func (s *busSnapshotSource) datasetJSON(_ context.Context, table, _, city string) ([]byte, time.Time, error) {
	key := table + "|" + city
	s.calls = append(s.calls, key)
	if err := s.errors[key]; err != nil {
		return nil, time.Time{}, err
	}
	return s.bodies[key], s.times[key], nil
}

func (s *busSnapshotSource) datasetJSONWithLandingCycle(_ context.Context, table, _, city string) ([]byte, time.Time, string, error) {
	key := table + "|" + city
	s.calls = append(s.calls, key)
	if err := s.errors[key]; err != nil {
		return nil, time.Time{}, "", err
	}
	return s.bodies[key], s.times[key], s.cycles[key], nil
}

func validBusSnapshotSource(city string) *busSnapshotSource {
	now := time.Now()
	prefix := citymap[city]
	bodies := map[string][]byte{
		"bus_route|" + city:        []byte(`[{"RouteUID":"TPE1","RouteName":{"Zh_tw":"1路"},"Operators":[{"OperatorID":"OP1"}],"SubRoutes":[{"SubRouteUID":"TPE100","SubRouteID":"100","SubRouteName":{"Zh_tw":"1路"},"Direction":0,"DepartureStopNameZh":"甲","DestinationStopNameZh":"乙","FirstBusTime":"06:00","LastBusTime":"23:00"}]}]`),
		"bus_stopofroute|" + city:  []byte(`[{"RouteUID":"TPE1","SubRouteUID":"TPE100","Direction":0,"Stops":[{"StopUID":"TPE_S1","StopName":{"Zh_tw":"甲站"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25.0}}]}]`),
		"bus_shape|" + city:        []byte(`[]`),
		"bus_schedule|" + city:     []byte(`[]`),
		"bus_station|" + city:      []byte(`[{"stationuid":"TPEST1","stationid":"ST1","stationname":{"Zh_tw":"甲站"},"stationposition":{"PositionLon":121.5,"PositionLat":25.0},"stationgroupid":"G1"}]`),
		"bus_stationgroup|" + city: []byte(`[]`),
		"bus_operator|" + city:     []byte(fmt.Sprintf(`[{"OperatorID":"OP1","OperatorName":{"Zh_tw":"測試客運"},"AuthorityCode":%q}]`, prefix)),
		"bus_routefare|" + city:    []byte(`[]`),
	}
	times := make(map[string]time.Time, len(bodies))
	cycles := make(map[string]string, len(bodies))
	for key := range bodies {
		times[key] = now
		cycles[key] = "cycle-current"
	}
	return &busSnapshotSource{bodies: bodies, times: times, cycles: cycles, errors: map[string]error{}}
}

func TestReadBusCitySnapshotAcceptsVerifiedEmptyOptionalDatasets(t *testing.T) {
	src := validBusSnapshotSource("Taipei")
	snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
	if err != nil {
		t.Fatalf("readBusCitySnapshot: %v", err)
	}
	if snapshot == nil || len(snapshot.subroutes) != 1 {
		t.Fatalf("snapshot = %#v, want one canonical subroute", snapshot)
	}
	if len(snapshot.scheduleRows) != 0 {
		t.Fatalf("schedule rows = %d, want verified empty", len(snapshot.scheduleRows))
	}
}

func TestReadBusCitySnapshotRejectsMissingOrStaleCorrelatedDataset(t *testing.T) {
	for _, test := range []struct {
		name string
		when time.Time
	}{
		{name: "missing landing state", when: time.Time{}},
		{name: "stale landing state", when: time.Now().Add(-staleAfter - time.Hour)},
	} {
		t.Run(test.name, func(t *testing.T) {
			src := validBusSnapshotSource("Taipei")
			src.times["bus_shape|Taipei"] = test.when
			_, err := readBusCitySnapshot(context.Background(), src, "Taipei")
			if !errors.Is(err, errBusSnapshotIncomplete) {
				t.Fatalf("error = %v, want errBusSnapshotIncomplete", err)
			}
		})
	}
}

func TestReadBusCitySnapshotRequiresOneDurableLandingCycleBeforeBegin(t *testing.T) {
	tests := []struct {
		name  string
		cycle string
	}{
		{name: "mixed cycle", cycle: "cycle-prior"},
		{name: "legacy state without cycle", cycle: ""},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			src := validBusSnapshotSource("Taipei")
			src.cycles["bus_shape|Taipei"] = test.cycle
			beginner := &recordingBusBeginner{tx: &recordingBusTx{}}
			snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
			if err == nil {
				err = writeBusCitySnapshot(context.Background(), beginner, snapshot)
			}
			if !errors.Is(err, errBusSnapshotIncomplete) {
				t.Fatalf("error = %v, want errBusSnapshotIncomplete", err)
			}
			if beginner.begins != 0 {
				t.Fatalf("target transaction began %d times for inconsistent cycle", beginner.begins)
			}
		})
	}
}

func TestReadBusCitySnapshotRejectsNullCorrelatedDataset(t *testing.T) {
	for _, table := range []string{
		"bus_route", "bus_stopofroute", "bus_shape", "bus_schedule",
		"bus_station", "bus_stationgroup", "bus_operator", "bus_routefare",
	} {
		t.Run(table, func(t *testing.T) {
			src := validBusSnapshotSource("Taipei")
			src.bodies[table+"|Taipei"] = []byte(`null`)
			if _, err := readBusCitySnapshot(context.Background(), src, "Taipei"); err == nil {
				t.Fatalf("%s null payload returned nil", table)
			}
		})
	}
}

func TestReadBusCitySnapshotReturnsEverySourceReadFailure(t *testing.T) {
	for _, table := range []string{
		"bus_route", "bus_stopofroute", "bus_shape", "bus_schedule",
		"bus_station", "bus_stationgroup", "bus_operator", "bus_routefare",
	} {
		t.Run(table, func(t *testing.T) {
			want := errors.New("read " + table)
			src := validBusSnapshotSource("Taipei")
			src.errors[table+"|Taipei"] = want
			if _, err := readBusCitySnapshot(context.Background(), src, "Taipei"); !errors.Is(err, want) {
				t.Fatalf("error = %v, want source error %v", err, want)
			}
		})
	}
}

func TestReadBusCitySnapshotRejectsForeignUIDsAndParentMismatchBeforeBegin(t *testing.T) {
	tests := []struct {
		name  string
		table string
		body  string
		city  string
	}{
		{
			name:  "route and subroute belong to another city",
			table: "bus_route",
			city:  "Taipei",
			body:  `[{"RouteUID":"NWT1","RouteName":{"Zh_tw":"1路"},"Operators":[{"OperatorID":"OP1"}],"SubRoutes":[{"SubRouteUID":"NWT100","SubRouteID":"100","SubRouteName":{"Zh_tw":"1路"},"Direction":0}]}]`,
		},
		{
			name:  "stop of route declares the wrong parent",
			table: "bus_stopofroute",
			city:  "Taipei",
			body:  `[{"RouteUID":"TPE_OTHER","SubRouteUID":"TPE100","Direction":0,"Stops":[{"StopUID":"TPE_S1","StopName":{"Zh_tw":"甲站"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25}}]}]`,
		},
		{
			name:  "schedule declares the wrong parent",
			table: "bus_schedule",
			city:  "Taipei",
			body:  `[{"RouteUID":"TPE_OTHER","SubRouteUID":"TPE100","Direction":0,"Frequencys":[{"StartTime":"06:00","EndTime":"07:00","MinHeadwayMins":5,"MaxHeadwayMins":10}]}]`,
		},
		{
			name:  "station belongs to another city",
			table: "bus_station",
			city:  "Taipei",
			body:  `[{"stationuid":"NWTST1","stationid":"ST1","stationname":{"Zh_tw":"甲站"},"stationposition":{"PositionLon":121.5,"PositionLat":25}}]`,
		},
		{
			name:  "station group belongs to another city",
			table: "bus_stationgroup",
			city:  "Taipei",
			body:  `[{"stationgroupuid":"NWTG1","stationgroupid":"G1","stationgroupname":{"Zh_tw":"甲站"},"stationgroupposition":{"PositionLon":121.5,"PositionLat":25}}]`,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			src := validBusSnapshotSource(test.city)
			src.bodies[test.table+"|"+test.city] = []byte(test.body)
			beginner := &recordingBusBeginner{tx: &recordingBusTx{}}
			snapshot, err := readBusCitySnapshot(context.Background(), src, test.city)
			if err == nil {
				err = writeBusCitySnapshot(context.Background(), beginner, snapshot)
			}
			if !errors.Is(err, errBusSnapshotInvalid) {
				t.Fatalf("error = %v, want errBusSnapshotInvalid", err)
			}
			if beginner.begins != 0 {
				t.Fatalf("target transaction began %d times for invalid source", beginner.begins)
			}
		})
	}
}

func TestReadBusCitySnapshotRejectsCanonicalSubrouteParentCollisionBeforeBegin(t *testing.T) {
	const city = "InterCity"
	src := validBusSnapshotSource(city)
	src.bodies["bus_operator|"+city] = []byte(`[{"OperatorID":"OP1","OperatorName":{"Zh_tw":"測試客運"},"AuthorityCode":"THB"}]`)
	src.bodies["bus_route|"+city] = []byte(`[
		{"RouteUID":"THB_A","RouteName":{"Zh_tw":"A"},"Operators":[{"OperatorID":"OP1"}],"SubRoutes":[{"SubRouteUID":"THB096801","SubRouteID":"096801","SubRouteName":{"Zh_tw":"A"},"Direction":0}]},
		{"RouteUID":"THB_B","RouteName":{"Zh_tw":"B"},"Operators":[{"OperatorID":"OP1"}],"SubRoutes":[{"SubRouteUID":"THB096802","SubRouteID":"096802","SubRouteName":{"Zh_tw":"B"},"Direction":0}]}
	]`)
	beginner := &recordingBusBeginner{tx: &recordingBusTx{}}
	snapshot, err := readBusCitySnapshot(context.Background(), src, city)
	if err == nil {
		err = writeBusCitySnapshot(context.Background(), beginner, snapshot)
	}
	if !errors.Is(err, errBusSnapshotConflict) {
		t.Fatalf("error = %v, want errBusSnapshotConflict", err)
	}
	if beginner.begins != 0 {
		t.Fatalf("target transaction began %d times for canonical collision", beginner.begins)
	}
}

func TestReadBusCitySnapshotRejectsMalformedOrDivergentOperatorsBeforeBegin(t *testing.T) {
	tests := []struct {
		name string
		body string
		want error
	}{
		{name: "missing authority", body: `[{"OperatorID":"OP1","OperatorName":{"Zh_tw":"測試客運"}}]`, want: errBusSnapshotInvalid},
		{name: "wrong authority", body: `[{"OperatorID":"OP1","OperatorName":{"Zh_tw":"測試客運"},"AuthorityCode":"NWT"}]`, want: errBusSnapshotInvalid},
		{name: "missing name", body: `[{"OperatorID":"OP1","AuthorityCode":"TPE"}]`, want: errBusSnapshotInvalid},
		{name: "divergent duplicate", body: `[
			{"OperatorID":"OP1","OperatorName":{"Zh_tw":"甲"},"AuthorityCode":"TPE"},
			{"OperatorID":"OP1","OperatorName":{"Zh_tw":"乙"},"AuthorityCode":"TPE"}
		]`, want: errBusSnapshotConflict},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			src := validBusSnapshotSource("Taipei")
			src.bodies["bus_operator|Taipei"] = []byte(test.body)
			beginner := &recordingBusBeginner{tx: &recordingBusTx{}}
			snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
			if err == nil {
				err = writeBusCitySnapshot(context.Background(), beginner, snapshot)
			}
			if !errors.Is(err, test.want) {
				t.Fatalf("error = %v, want %v", err, test.want)
			}
			if beginner.begins != 0 {
				t.Fatalf("target transaction began %d times for invalid operators", beginner.begins)
			}
		})
	}
}

func TestReadBusCitySnapshotUsesCanonicalInterCityDirectionForEndpoints(t *testing.T) {
	const city = "InterCity"
	src := validBusSnapshotSource(city)
	src.bodies["bus_operator|"+city] = []byte(`[{"OperatorID":"OP1","OperatorName":{"Zh_tw":"測試客運"},"AuthorityCode":"THB"}]`)
	src.bodies["bus_route|"+city] = []byte(`[{"RouteUID":"THB0968","RouteName":{"Zh_tw":"0968"},"DepartureStopNameZh":"甲","DestinationStopNameZh":"乙","Operators":[{"OperatorID":"OP1"}],"SubRoutes":[
		{"SubRouteUID":"THB096801","SubRouteID":"096801","SubRouteName":{"Zh_tw":"0968"},"Direction":9},
		{"SubRouteUID":"THB096802","SubRouteID":"096802","SubRouteName":{"Zh_tw":"0968"},"Direction":9}
	]}]`)
	src.bodies["bus_stopofroute|"+city] = []byte(`[
		{"RouteUID":"THB0968","SubRouteUID":"THB096801","Direction":9,"Stops":[{"StopUID":"THB_S1","StopName":{"Zh_tw":"甲"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25}}]},
		{"RouteUID":"THB0968","SubRouteUID":"THB096802","Direction":9,"Stops":[{"StopUID":"THB_S1","StopName":{"Zh_tw":"甲"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25}}]}
	]`)
	src.bodies["bus_station|"+city] = []byte(`[{"stationuid":"THBST1","stationid":"ST1","stationname":{"Zh_tw":"甲"},"stationposition":{"PositionLon":121.5,"PositionLat":25}}]`)
	snapshot, err := readBusCitySnapshot(context.Background(), src, city)
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	route := snapshot.subroutes["THB0968"]
	if route == nil {
		t.Fatal("canonical route THB0968 missing")
	}
	if got := route.Directions[0]; got == nil || got.DepartureStopName != "甲" || got.DestinationStopName != "乙" {
		t.Fatalf("direction 0 endpoints = %#v, want 甲 -> 乙", got)
	}
	if got := route.Directions[1]; got == nil || got.DepartureStopName != "乙" || got.DestinationStopName != "甲" {
		t.Fatalf("direction 1 endpoints = %#v, want 乙 -> 甲", got)
	}
}

func TestDecodeStrictJSONArrayRejectsMalformedTrailingData(t *testing.T) {
	var target []json.RawMessage
	if err := decodeStrictJSONArray([]byte(`[] x]`), &target); err == nil {
		t.Fatal("malformed trailing data returned nil")
	}
}

func TestReadBusCitySnapshotRejectsZeroValidRoutesAndMalformedElement(t *testing.T) {
	for _, body := range []string{
		`[]`,
		`null`,
		`[{"RouteUID":"","RouteName":{"Zh_tw":""},"SubRoutes":[]}]`,
		`[{"RouteUID":`,
	} {
		src := validBusSnapshotSource("Taipei")
		src.bodies["bus_route|Taipei"] = []byte(body)
		if _, err := readBusCitySnapshot(context.Background(), src, "Taipei"); err == nil {
			t.Fatalf("route body %q returned nil error", body)
		}
	}
}

func TestReadBusCitySnapshotPreservesIntentionalScheduleDuplicates(t *testing.T) {
	src := validBusSnapshotSource("Taipei")
	src.bodies["bus_schedule|Taipei"] = []byte(`[{"RouteUID":"TPE1","SubRouteUID":"TPE100","Direction":0,"Timetables":[{"TripID":"CIRCULAR","ServiceDay":{"Monday":1},"StopTimes":[
		{"StopSequence":1,"StopUID":"S1","StopName":{"Zh_tw":"甲"},"ArrivalTime":"08:00","DepartureTime":"08:01"},
		{"StopSequence":2,"StopUID":"S1","StopName":{"Zh_tw":"甲"},"ArrivalTime":"08:20","DepartureTime":"08:21"}
	]}]}]`)
	snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if got := len(snapshot.scheduleRows); got != 2 {
		t.Fatalf("circular schedule rows = %d, want 2", got)
	}
}

func TestReadBusCitySnapshotBuildsDeterministicManualGroupCentroid(t *testing.T) {
	src := validBusSnapshotSource("Taipei")
	src.bodies["bus_station|Taipei"] = []byte(`[
		{"stationuid":"TPEST1","stationid":"ST1","stationname":{"Zh_tw":"同名站"},"stationposition":{"PositionLon":121.4,"PositionLat":25.0}},
		{"stationuid":"TPEST2","stationid":"ST2","stationname":{"Zh_tw":"同名站"},"stationposition":{"PositionLon":121.6,"PositionLat":25.2}}
	]`)
	snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if len(snapshot.groupRows) != 1 || len(snapshot.memberRows) != 2 {
		t.Fatalf("groups/members = %d/%d, want 1/2", len(snapshot.groupRows), len(snapshot.memberRows))
	}
	if lon, lat := snapshot.groupRows[0][3].(float64), snapshot.groupRows[0][4].(float64); lon != 121.5 || lat != 25.1 {
		t.Fatalf("manual centroid = (%v,%v), want (121.5,25.1)", lon, lat)
	}
}

func TestReadBusCitySnapshotDeduplicatesIdenticalStopsAndRejectsDivergence(t *testing.T) {
	src := validBusSnapshotSource("Taipei")
	one := string(src.bodies["bus_stopofroute|Taipei"])
	src.bodies["bus_stopofroute|Taipei"] = []byte("[" + one[1:len(one)-1] + "," + one[1:len(one)-1] + "]")
	snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
	if err != nil {
		t.Fatalf("identical duplicate: %v", err)
	}
	if got := len(snapshot.subroutes["TPE100"].Directions[0].Stops); got != 1 {
		t.Fatalf("deduplicated stops = %d, want 1", got)
	}

	src = validBusSnapshotSource("Taipei")
	src.bodies["bus_stopofroute|Taipei"] = []byte(`[
		{"RouteUID":"TPE1","SubRouteUID":"TPE100","Direction":0,"Stops":[{"StopUID":"S1","StopName":{"Zh_tw":"甲"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25}}]},
		{"RouteUID":"TPE1","SubRouteUID":"TPE100","Direction":0,"Stops":[{"StopUID":"S2","StopName":{"Zh_tw":"乙"},"StopSequence":1,"StationID":"ST2","StopPosition":{"PositionLon":121.6,"PositionLat":25}}]}
	]`)
	if _, err := readBusCitySnapshot(context.Background(), src, "Taipei"); !errors.Is(err, errBusSnapshotConflict) {
		t.Fatalf("divergent duplicate error = %v, want errBusSnapshotConflict", err)
	}
}

func TestReadBusCitySnapshotMapsNativeFareAndRejectsDivergentCanonicalOffers(t *testing.T) {
	const city = "InterCity"
	src := validBusSnapshotSource(city)
	src.bodies["bus_route|"+city] = []byte(`[{"RouteUID":"THB0968","RouteName":{"Zh_tw":"0968"},"SubRoutes":[{"SubRouteUID":"THB096801","SubRouteID":"096801","SubRouteName":{"Zh_tw":"0968"},"Direction":0}]}]`)
	src.bodies["bus_stopofroute|"+city] = []byte(`[{"RouteUID":"THB0968","SubRouteUID":"THB096801","Direction":0,"Stops":[{"StopUID":"S1","StopName":{"Zh_tw":"甲"},"StopSequence":1,"StationID":"ST1","StopPosition":{"PositionLon":121.5,"PositionLat":25}}]}]`)
	src.bodies["bus_station|"+city] = []byte(`[{"stationuid":"THBST1","stationid":"ST1","stationname":{"Zh_tw":"甲"},"stationposition":{"PositionLon":121.5,"PositionLat":25}}]`)
	src.bodies["bus_routefare|"+city] = []byte(`[{"RouteID":"0968","SubRouteID":"096801","FarePricingType":1,"IsFreeBus":0}]`)
	snapshot, err := readBusCitySnapshot(context.Background(), src, city)
	if err != nil {
		t.Fatalf("native fare: %v", err)
	}
	if snapshot.subroutes["THB0968"].Fare == nil {
		t.Fatal("canonical subroute did not receive native SubRouteID fare")
	}

	src.bodies["bus_routefare|"+city] = []byte(`[
		{"RouteID":"0968","SubRouteID":"096801","FarePricingType":1},
		{"RouteID":"0968","SubRouteID":"096802","FarePricingType":2}
	]`)
	if _, err := readBusCitySnapshot(context.Background(), src, city); !errors.Is(err, errBusSnapshotConflict) {
		t.Fatalf("divergent fare error = %v, want errBusSnapshotConflict", err)
	}
}

type recordingBusTx struct {
	execs               []string
	copies              []string
	failSQL             string
	failCopy            string
	queryErr            error
	unsafeGroupRekey    bool
	commitErr           error
	committed           bool
	rolledBack          bool
	rollbackContextLive bool
}

func (tx *recordingBusTx) Exec(_ context.Context, sql string, _ ...any) (pgconn.CommandTag, error) {
	tx.execs = append(tx.execs, sql)
	if tx.failSQL != "" && strings.Contains(sql, tx.failSQL) {
		return pgconn.CommandTag{}, errors.New("injected exec failure")
	}
	return pgconn.NewCommandTag("OK"), nil
}

func (tx *recordingBusTx) CopyFrom(_ context.Context, table pgx.Identifier, _ []string, _ pgx.CopyFromSource) (int64, error) {
	name := table.Sanitize()
	tx.copies = append(tx.copies, name)
	if tx.failCopy != "" && strings.Contains(name, tx.failCopy) {
		return 0, errors.New("injected copy failure")
	}
	return 1, nil
}

func (tx *recordingBusTx) QueryRow(_ context.Context, _ string, _ ...any) pgx.Row {
	return boolRow{value: tx.unsafeGroupRekey, err: tx.queryErr}
}

func (tx *recordingBusTx) Commit(_ context.Context) error {
	if tx.commitErr != nil {
		return tx.commitErr
	}
	tx.committed = true
	return nil
}

func (tx *recordingBusTx) Rollback(ctx context.Context) error {
	tx.rolledBack = true
	tx.rollbackContextLive = ctx.Err() == nil
	return nil
}

type boolRow struct {
	value bool
	err   error
}

func (r boolRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(dest) != 1 {
		return fmt.Errorf("destinations = %d, want 1", len(dest))
	}
	value, ok := dest[0].(*bool)
	if !ok {
		return fmt.Errorf("destination is %T, want *bool", dest[0])
	}
	*value = r.value
	return nil
}

type recordingBusBeginner struct {
	tx       *recordingBusTx
	beginErr error
	begins   int
}

func (b *recordingBusBeginner) BeginBusTx(context.Context) (busTx, error) {
	b.begins++
	if b.beginErr != nil {
		return nil, b.beginErr
	}
	return b.tx, nil
}

func mustValidBusSnapshot(t *testing.T) *busCitySnapshot {
	t.Helper()
	snapshot, err := readBusCitySnapshot(context.Background(), validBusSnapshotSource("Taipei"), "Taipei")
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	return snapshot
}

func TestBusScheduleRowsUseDepartureTime(t *testing.T) {
	src := validBusSnapshotSource("Taipei")
	src.bodies["bus_schedule|Taipei"] = []byte(`[{"RouteUID":"TPE1","SubRouteUID":"TPE100","Direction":0,"Timetables":[{"TripID":"TRIP","ServiceDay":{"Monday":1},"StopTimes":[{"StopSequence":1,"StopUID":"S1","StopName":{"Zh_tw":"甲"},"ArrivalTime":"08:00","DepartureTime":"08:03"}]}]}]`)
	snapshot, err := readBusCitySnapshot(context.Background(), src, "Taipei")
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if got := snapshot.scheduleRows[0][9]; got != "08:03" {
		t.Fatalf("departure column = %v, want 08:03", got)
	}
}

func TestWriteBusCitySnapshotRollsBackStationMapAndUsesLiveRollbackContext(t *testing.T) {
	tx := &recordingBusTx{failSQL: "INSERT INTO bus_station_stop_map"}
	beginner := &recordingBusBeginner{tx: tx}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := writeBusCitySnapshot(ctx, beginner, mustValidBusSnapshot(t))
	if err == nil {
		t.Fatal("injected stop-map failure returned nil")
	}
	if tx.committed {
		t.Fatal("transaction committed after stop-map failure")
	}
	if !tx.rolledBack || !tx.rollbackContextLive {
		t.Fatalf("rollback = %v, live context = %v", tx.rolledBack, tx.rollbackContextLive)
	}
}

func TestWriteBusCitySnapshotClearsEmptyScheduleAndPrunesInDependencyOrder(t *testing.T) {
	tx := &recordingBusTx{}
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err != nil {
		t.Fatalf("write snapshot: %v", err)
	}
	joined := strings.Join(tx.execs, "\n")
	for _, required := range []string{
		"DELETE FROM bus_schedule", "DELETE FROM bus_stations", "DELETE FROM bus_station_group_members", "DELETE FROM bus_station_groups",
	} {
		if !strings.Contains(joined, required) {
			t.Fatalf("writer did not execute %q", required)
		}
	}
	memberPrune := indexSQL(tx.execs, "DELETE FROM bus_station_group_members")
	emptyGroupPrune := indexSQL(tx.execs, "NOT EXISTS (SELECT 1 FROM bus_station_group_members")
	if memberPrune < 0 || emptyGroupPrune < 0 || memberPrune >= emptyGroupPrune {
		t.Fatalf("member prune index=%d, empty-group prune index=%d, want member first", memberPrune, emptyGroupPrune)
	}
	if !tx.committed {
		t.Fatal("valid snapshot did not commit")
	}
}

func TestBusSubrouteUpsertRefreshesMutableFieldsAndUsesStationID(t *testing.T) {
	for _, field := range []string{"route_uid = EXCLUDED.route_uid", "route_name = EXCLUDED.route_name", "sub_route_name = EXCLUDED.sub_route_name", "s ->> 'StationID'"} {
		if !strings.Contains(busSubroutesUpsertSQL, field) {
			t.Fatalf("busSubroutesUpsertSQL missing %q", field)
		}
	}
	if strings.Contains(busSubroutesUpsertSQL, "s ->> 'StationUID'") {
		t.Fatal("busSubroutesUpsertSQL still extracts nonexistent StationUID")
	}
}

func TestWriteBusCitySnapshotReturnsBeginAndCommitFailures(t *testing.T) {
	beginErr := errors.New("begin failed")
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{beginErr: beginErr}, mustValidBusSnapshot(t)); !errors.Is(err, beginErr) {
		t.Fatalf("begin error = %v, want %v", err, beginErr)
	}
	commitErr := errors.New("commit failed")
	tx := &recordingBusTx{commitErr: commitErr}
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); !errors.Is(err, commitErr) {
		t.Fatalf("commit error = %v, want %v", err, commitErr)
	}
	if !tx.rolledBack || !tx.rollbackContextLive {
		t.Fatal("commit failure did not receive bounded background rollback")
	}
	queryErr := errors.New("rekey query failed")
	tx = &recordingBusTx{queryErr: queryErr}
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); !errors.Is(err, queryErr) {
		t.Fatalf("rekey query error = %v, want %v", err, queryErr)
	}
}

func TestWriteBusCitySnapshotReturnsEveryStageFailure(t *testing.T) {
	for _, temp := range []string{
		"temp_bus", "temp_bus_operators", "temp_bus_stations", "temp_bus_groups", "temp_bus_members",
		"temp_bus_schedule", "temp_bus_static", "temp_bus_stop_map",
	} {
		t.Run("create "+temp, func(t *testing.T) {
			tx := &recordingBusTx{failSQL: "CREATE TEMP TABLE " + temp + " "}
			if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err == nil {
				t.Fatalf("create %s failure returned nil", temp)
			}
		})
		t.Run("copy "+temp, func(t *testing.T) {
			tx := &recordingBusTx{failCopy: temp}
			if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err == nil {
				t.Fatalf("copy %s failure returned nil", temp)
			}
		})
	}
	for _, fragment := range []string{
		"SET LOCAL lock_timeout",
		"INSERT INTO bus_subroutes", "INSERT INTO bus_operators", "INSERT INTO bus_stations", "INSERT INTO bus_station_groups",
		"INSERT INTO bus_station_group_members", "DELETE FROM bus_schedule", "INSERT INTO bus_schedule",
		"INSERT INTO bus_static", "DELETE FROM bus_station_stop_map", "INSERT INTO bus_station_stop_map",
		"DELETE FROM bus_station_group_members", "DELETE FROM bus_station_groups current",
		"DELETE FROM bus_stations", "DELETE FROM bus_subroutes", "DELETE FROM bus_static", "DELETE FROM bus_operators",
	} {
		t.Run(fragment, func(t *testing.T) {
			tx := &recordingBusTx{failSQL: fragment}
			if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err == nil {
				t.Fatalf("%s failure returned nil", fragment)
			}
			if tx.committed {
				t.Fatalf("%s failure committed", fragment)
			}
		})
	}
}

func TestWriteBusCitySnapshotRollsBackOperatorsWithLaterFailure(t *testing.T) {
	tx := &recordingBusTx{failSQL: "INSERT INTO bus_static"}
	err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t))
	if err == nil {
		t.Fatal("later static failure returned nil")
	}
	if indexSQL(tx.execs, "INSERT INTO bus_operators") < 0 {
		t.Fatal("writer did not stage operator target write before later failure")
	}
	if tx.committed || !tx.rolledBack {
		t.Fatalf("committed/rolledBack = %v/%v, want false/true", tx.committed, tx.rolledBack)
	}
}

func TestWriteBusCitySnapshotUsesStableInterCityGroupTieBreak(t *testing.T) {
	tx := &recordingBusTx{}
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err != nil {
		t.Fatalf("write snapshot: %v", err)
	}
	var memberUpsert string
	for _, statement := range tx.execs {
		if strings.Contains(statement, "INSERT INTO bus_station_group_members") {
			memberUpsert = statement
			break
		}
	}
	orderStart := strings.Index(memberUpsert, "ORDER BY")
	limitStart := strings.Index(memberUpsert, "LIMIT 1")
	if orderStart < 0 || limitStart < orderStart || !strings.Contains(memberUpsert[orderStart:limitStart], "g.group_uid") {
		t.Fatalf("member upsert lacks stable group_uid tie-break: %s", memberUpsert)
	}
}

func TestWriteBusCitySnapshotRejectsUnsafeGroupRekeyBeforeTargetWrite(t *testing.T) {
	tx := &recordingBusTx{unsafeGroupRekey: true}
	err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t))
	if !errors.Is(err, errBusSnapshotConflict) {
		t.Fatalf("rekey error = %v, want errBusSnapshotConflict", err)
	}
	for _, statement := range tx.execs {
		if strings.Contains(statement, "INSERT INTO bus_") {
			t.Fatalf("unsafe rekey performed target write: %s", statement)
		}
	}
}

func TestWriteBusCitySnapshotNeverReadsRawTDXFromTarget(t *testing.T) {
	tx := &recordingBusTx{}
	if err := writeBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, mustValidBusSnapshot(t)); err != nil {
		t.Fatalf("write snapshot: %v", err)
	}
	for _, statement := range tx.execs {
		if strings.Contains(strings.ToLower(statement), "raw_tdx") {
			t.Fatalf("target transaction accessed raw database: %s", statement)
		}
	}
}

func TestInvalidateBusStaticAfterCommitReturnsRedisFailureAndDropsOnlyCity(t *testing.T) {
	storeBusStaticMapIn(&busStaticMapCache, "TPE", []busStationmap{{StopUID: "old-tpe"}}, "1", time.Now())
	storeBusStaticMapIn(&busStaticMapCache, "NWT", []busStationmap{{StopUID: "old-nwt"}}, "1", time.Now())
	t.Cleanup(invalidateBusStaticMap)
	if err := invalidateBusStaticAfterCommit(nil, "Taipei"); err == nil {
		t.Fatal("nil Redis returned nil post-commit invalidation error")
	}
	if _, ok := busStaticMapCache.Load("TPE"); ok {
		t.Fatal("Taipei local cache was not invalidated")
	}
	if _, ok := busStaticMapCache.Load("NWT"); !ok {
		t.Fatal("Taipei invalidation cleared unrelated NewTaipei cache")
	}
}

func TestPersistBusCitySnapshotInvalidatesOnlyAfterCommit(t *testing.T) {
	snapshot := mustValidBusSnapshot(t)
	tx := &recordingBusTx{}
	cacheErr := errors.New("redis unavailable")
	invalidated := false
	err := persistBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, snapshot, func() error {
		invalidated = true
		if !tx.committed {
			t.Fatal("cache invalidation ran before transaction commit")
		}
		return cacheErr
	})
	if !errors.Is(err, errBusPostCommitCache) || !errors.Is(err, cacheErr) {
		t.Fatalf("post-commit error = %v, want cache sentinel and cause", err)
	}
	if !invalidated {
		t.Fatal("successful commit did not invoke cache invalidation")
	}

	tx = &recordingBusTx{failSQL: "INSERT INTO bus_station_stop_map"}
	invalidated = false
	if err := persistBusCitySnapshot(context.Background(), &recordingBusBeginner{tx: tx}, snapshot, func() error {
		invalidated = true
		return nil
	}); err == nil {
		t.Fatal("target write failure returned nil")
	}
	if invalidated {
		t.Fatal("failed transaction invoked cache invalidation")
	}
}

func indexSQL(statements []string, fragment string) int {
	for i, statement := range statements {
		if strings.Contains(statement, fragment) {
			return i
		}
	}
	return -1
}
