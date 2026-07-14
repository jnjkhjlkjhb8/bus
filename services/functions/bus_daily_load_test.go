package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

func unavailableRedisClient() *redis.Client {
	return redis.NewClient(&redis.Options{
		Addr:         "127.0.0.1:1",
		DialTimeout:  time.Millisecond,
		ReadTimeout:  time.Millisecond,
		WriteTimeout: time.Millisecond,
		MaxRetries:   0,
	})
}

func TestLoadBusDailyTimetableRejectsInvalidIdentityTimeOrDirection(t *testing.T) {
	tests := []struct {
		name string
		body string
		want string
	}{
		{
			name: "missing subroute",
			body: `[{"Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "SubRouteUID",
		},
		{
			name: "invalid direction",
			body: `[{"SubRouteUID":"KHH1","Direction":2,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "Direction",
		},
		{
			name: "missing direction",
			body: `[{"SubRouteUID":"KHH1","Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "Direction",
		},
		{
			name: "invalid arrival",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"24:00","DepartureTime":"08:01"}]}]}]`,
			want: "ArrivalTime",
		},
		{
			name: "missing trip ID",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "TripID",
		},
		{
			name: "empty stop times",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[]}]}]`,
			want: "StopTimes",
		},
		{
			name: "zero stop sequence",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":0,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "StopSequence",
		},
		{
			name: "stop sequence exceeds protobuf int32",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":2147483648,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "StopSequence",
		},
		{
			name: "missing stop UID",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "StopUID",
		},
		{
			name: "invalid departure",
			body: `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"xx"}]}]}]`,
			want: "DepartureTime",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rc := unavailableRedisClient()
			defer rc.Close()
			err := loadBusDailyTimetable(context.Background(), decodeInto(tt.body), nil, rc, "Kaohsiung")
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("loadBusDailyTimetable error = %v, want %q", err, tt.want)
			}
		})
	}
}

func TestLoadBusDailyTimetableRejectsInvalidCanonicalIdentityBeforeRedis(t *testing.T) {
	tests := []struct {
		name string
		city string
		body string
		want string
	}{
		{
			name: "InterCity suffix canonicalizes to empty",
			city: "InterCity",
			body: `[{"SubRouteUID":"01","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "canonical SubRouteUID",
		},
		{
			name: "wrong city authority prefix",
			city: "Kaohsiung",
			body: `[{"SubRouteUID":"TPE1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`,
			want: "authority",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rc := unavailableRedisClient()
			defer rc.Close()
			err := loadBusDailyTimetable(context.Background(), decodeInto(tt.body), nil, rc, tt.city)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("loadBusDailyTimetable error = %v, want pre-Redis %q validation", err, tt.want)
			}
		})
	}
}

func TestLoadBusDailyTimetableMalformedSuffixWritesNoKeys(t *testing.T) {
	rc := redis.NewClient(&redis.Options{Addr: "127.0.0.1:6379", DialTimeout: 200 * time.Millisecond, MaxRetries: 0})
	defer rc.Close()
	if err := rc.Ping().Err(); err != nil {
		t.Skipf("local Redis not reachable: %v", err)
	}
	const uid = "ZZ_TASK5_NO_PARTIAL"
	key := shared.BusDailyTimetableKey(uid)
	_ = rc.Del(key).Err()
	defer func() { _ = rc.Del(key).Err() }()

	body := `[
		{"SubRouteUID":"` + uid + `","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]},
		{"SubRouteUID":
	]`
	err := loadBusDailyTimetable(context.Background(), decodeInto(body), nil, rc, "Kaohsiung")
	if err == nil || !strings.Contains(err.Error(), "element 1") {
		t.Fatalf("loadBusDailyTimetable error = %v, want wrapped element 1 decode error", err)
	}
	if exists := rc.Exists(key).Val(); exists != 0 {
		t.Fatalf("Redis key %s exists after malformed suffix", key)
	}
}

func TestLoadBusDailyTimetableReturnsPipelineError(t *testing.T) {
	rc := unavailableRedisClient()
	defer rc.Close()
	body := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`
	err := loadBusDailyTimetable(context.Background(), decodeInto(body), nil, rc, "Kaohsiung")
	if err == nil || !strings.Contains(err.Error(), "Redis transaction") {
		t.Fatalf("loadBusDailyTimetable error = %v, want wrapped Redis transaction error", err)
	}
}

func TestLoadBusDailyTimetableDuplicateTripPolicy(t *testing.T) {
	rc := redis.NewClient(&redis.Options{Addr: "127.0.0.1:6379", DialTimeout: 200 * time.Millisecond, MaxRetries: 0})
	defer rc.Close()
	if err := rc.Ping().Err(); err != nil {
		t.Skipf("local Redis not reachable: %v", err)
	}
	key := shared.BusDailyTimetableKey("KHH1")
	_ = rc.Del(key).Err()
	defer func() { _ = rc.Del(key).Err() }()
	trip := `{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}`
	identical := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[` + trip + `,` + trip + `]}]`
	if err := loadBusDailyTimetable(context.Background(), decodeInto(identical), nil, rc, "Kaohsiung"); err != nil {
		t.Fatalf("identical duplicate: %v", err)
	}
	bytes, err := rc.Get(key).Bytes()
	if err != nil {
		t.Fatalf("read deduped timetable: %v", err)
	}
	var got models.Bus_DailyTimetables
	if err := proto.Unmarshal(bytes, &got); err != nil {
		t.Fatalf("unmarshal deduped timetable: %v", err)
	}
	if len(got.Direction[0].DailyTimetables) != 1 {
		t.Fatalf("daily timetables = %d, want one identical trip", len(got.Direction[0].DailyTimetables))
	}
	if stopUID := got.Direction[0].DailyTimetables[0].StopTimes[0].StopUID; stopUID != "S1" {
		t.Fatalf("persisted StopUID = %q, want S1", stopUID)
	}
	other := `{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S2","ArrivalTime":"08:00","DepartureTime":"08:01"}]}`
	divergent := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[` + trip + `,` + other + `]}]`
	err = loadBusDailyTimetable(context.Background(), decodeInto(divergent), nil, rc, "Kaohsiung")
	if err == nil || !strings.Contains(err.Error(), "duplicate TripID") {
		t.Fatalf("divergent duplicate error = %v, want duplicate TripID error", err)
	}
}

func TestLoadBusDailyTimetableDuplicateStopSequencePolicy(t *testing.T) {
	rc := redis.NewClient(&redis.Options{Addr: "127.0.0.1:6379", DialTimeout: 200 * time.Millisecond, MaxRetries: 0})
	defer rc.Close()
	if err := rc.Ping().Err(); err != nil {
		t.Skipf("local Redis not reachable: %v", err)
	}
	key := shared.BusDailyTimetableKey("KHH1")
	_ = rc.Del(key).Err()
	defer func() { _ = rc.Del(key).Err() }()
	stop := `{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}`
	identical := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[` + stop + `,` + stop + `]}]}]`
	if err := loadBusDailyTimetable(context.Background(), decodeInto(identical), nil, rc, "Kaohsiung"); err != nil {
		t.Fatalf("identical duplicate stop: %v", err)
	}
	before, err := rc.Get(key).Bytes()
	if err != nil {
		t.Fatalf("read deduped timetable: %v", err)
	}
	var got models.Bus_DailyTimetables
	if err := proto.Unmarshal(before, &got); err != nil {
		t.Fatalf("unmarshal deduped timetable: %v", err)
	}
	if stops := got.Direction[0].DailyTimetables[0].StopTimes; len(stops) != 1 {
		t.Fatalf("deduped stops = %+v, want one target stop", stops)
	}

	other := `{"StopSequence":1,"StopUID":"S2","ArrivalTime":"08:00","DepartureTime":"08:01"}`
	divergent := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[` + stop + `,` + other + `]}]}]`
	err = loadBusDailyTimetable(context.Background(), decodeInto(divergent), nil, rc, "Kaohsiung")
	if err == nil || !strings.Contains(err.Error(), "duplicate StopSequence") {
		t.Fatalf("divergent duplicate stop error = %v, want duplicate StopSequence", err)
	}
	after, err := rc.Get(key).Bytes()
	if err != nil {
		t.Fatalf("read timetable after rejected duplicate: %v", err)
	}
	if string(after) != string(before) {
		t.Fatal("divergent duplicate stop mutated Redis")
	}
}

func TestLoadBusDailyTimetableObservesCancellationDuringRedisExec(t *testing.T) {
	rc := unavailableRedisClient()
	defer rc.Close()
	entered := make(chan struct{})
	release := make(chan struct{})
	rc.WrapProcessPipeline(func(_ func([]redis.Cmder) error) func([]redis.Cmder) error {
		return func(_ []redis.Cmder) error {
			close(entered)
			<-release
			return nil
		}
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	body := `[{"SubRouteUID":"KHH1","Direction":0,"Timetables":[{"TripID":"T1","StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`
	go func() {
		done <- loadBusDailyTimetable(ctx, decodeInto(body), nil, rc, "Kaohsiung")
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("Redis Exec was not entered")
	}
	if err := ctx.Err(); err != nil {
		t.Fatalf("context canceled before Redis Exec: %v", err)
	}
	cancel()
	close(release)
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) || !strings.Contains(err.Error(), "context during Redis transaction") {
			t.Fatalf("loadBusDailyTimetable error = %v, want wrapped in-Exec cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("loadBusDailyTimetable did not return after Redis Exec release")
	}
}
