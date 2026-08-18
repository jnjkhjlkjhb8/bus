package main

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"google.golang.org/protobuf/proto"
)

func (s *busCitySnapshot) buildWriteRows() error {
	uids := make([]string, 0, len(s.subroutes))
	for uid := range s.subroutes {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	for _, uid := range uids {
		sub := s.subroutes[uid]
		pb, err := (proto.MarshalOptions{Deterministic: true}).Marshal(sub)
		if err != nil {
			return _oops.With("uid", uid).Wrapf(err, "marshal protobuf")
		}
		s.staticRows = append(s.staticRows, []any{sub.SubRouteName, sub.RouteName, sub.SubRouteUID, sub.RouteUID, sub.City, sub.DepartureStopName, sub.DestinationStopName, pb})
		dirs := make([]int, 0, len(sub.Directions))
		for dir := range sub.Directions {
			dirs = append(dirs, int(dir))
		}
		sort.Ints(dirs)
		for _, rawDir := range dirs {
			dir := int32(rawDir)
			direction := sub.Directions[dir]
			stops, err := json.Marshal(direction.Stops)
			if err != nil {
				return _oops.With("uid", uid).With("dir", dir).Wrapf(err, "marshal / stops")
			}
			schedules, err := json.Marshal(direction.Schedules)
			if err != nil {
				return _oops.With("uid", uid).With("dir", dir).Wrapf(err, "marshal / schedules")
			}
			ops := make([]busOperatorJSON, 0, len(sub.Operators))
			for _, op := range sub.Operators {
				ops = append(ops, busOperatorJSON{ID: op.OperatorId, Name: op.OperatorName, Phone: op.OperatorPhone, URL: op.OperatorUrl})
			}
			operators, err := json.Marshal(ops)
			if err != nil {
				return _oops.With("uid", uid).Wrapf(err, "marshal operators")
			}
			s.subrouteRows = append(s.subrouteRows, []any{
				sub.SubRouteUID, sub.RouteUID, dir, sub.RouteName, sub.SubRouteName, sub.City,
				direction.DepartureStopName, direction.DestinationStopName, direction.Geometry,
				stops, schedules, operators,
			})
			for _, stop := range direction.Stops {
				s.stopMapRows = append(s.stopMapRows, []any{
					prefixID(s.prefix, stop.StationID), stop.StopName, sub.SubRouteUID,
					sub.SubRouteName, dir, stop.StopUID, stop.StopSequence,
				})
			}
		}
	}
	return nil
}

// busStopAliasRows pairs a discarded operator's stop list against the kept one
// by stop sequence — the position in the run is what the two lists agree on,
// since the whole point is that their StopUIDs differ — and returns one alias
// row per position whose UID actually differs. Positions the kept list does not
// have are skipped: an alias may only point at a stop the ETA join can reach.
func busStopAliasRows(uid string, dir uint8, kept, discarded rawStopofroute) [][]any {
	keptBySequence := make(map[uint8]string, len(kept.Stops))
	for _, stop := range kept.Stops {
		keptBySequence[stop.StopSequence] = stop.StopUID
	}
	rows := make([][]any, 0, len(discarded.Stops))
	for _, stop := range discarded.Stops {
		canonical, ok := keptBySequence[stop.StopSequence]
		if !ok || canonical == stop.StopUID {
			continue
		}
		rows = append(rows, []any{uid, int16(dir), stop.StopUID, canonical})
	}
	return rows
}

func buildScheduleRows(uid string, dir uint8, schedule rawBusSchedule) ([][]any, []*models.Bus_Schedule, error) {
	var rows [][]any
	var modelRows []*models.Bus_Schedule
	for _, timetable := range schedule.Timetables {
		if timetable.TripID == "" {
			return nil, nil, errors.New("timetable has empty TripID")
		}
		service := mask2(timetable.ServiceDay.Monday, timetable.ServiceDay.Tuesday, timetable.ServiceDay.Wednesday, timetable.ServiceDay.Thursday, timetable.ServiceDay.Friday, timetable.ServiceDay.Saturday, timetable.ServiceDay.Sunday)
		// The DB keeps every stop of the trip (segment times and ETA prediction
		// read them); the proto payload carries only the origin, since the app's
		// timetable board lists departures. TDX does not promise StopTimes are
		// sorted, so the origin is the lowest StopSequence rather than the first
		// element.
		var origin *models.Bus_Schedule
		var originSeq int
		for _, stop := range timetable.StopTimes {
			// The upper bound is the bus_schedule.stop_sequence SMALLINT column: an
			// out-of-range sequence would wrap to a negative on the int16 cast below.
			seqInRange := stop.StopSequence > 0 && stop.StopSequence <= math.MaxInt16
			hasIdentity := stop.StopUID != "" && stop.StopName.Zhtw != ""
			hasClocks := validClock(stop.ArrivalTime) && validClock(stop.DepartureTime)
			if !seqInRange || !hasIdentity || !hasClocks {
				return nil, nil, _oops.With("trip_id", timetable.TripID).Errorf("trip has invalid stop identity/sequence/time")
			}
			rows = append(rows, []any{uid, int16(dir), false, timetable.TripID, timetable.IsLowFloor, int16(stop.StopSequence), stop.StopUID, stop.StopName.Zhtw, stop.ArrivalTime, stop.DepartureTime, int16(service)})
			if origin != nil && stop.StopSequence >= originSeq {
				continue
			}
			originSeq = stop.StopSequence
			origin = &models.Bus_Schedule{
				IsTimetable: true, Tripid: timetable.TripID, Islowfloor: timetable.IsLowFloor,
				MinHeadwayMinsArrivalTime: stop.ArrivalTime, MaxHeadwayMinsDepartureTime: stop.DepartureTime,
				ServiceDay: int32(service),
			}
		}
		if origin != nil {
			modelRows = append(modelRows, origin)
		}
	}
	for _, frequency := range schedule.Frequencys {
		hasClocks := validClock(frequency.StartTime) && validClock(frequency.EndTime)
		hasHeadway := frequency.MinHeadwayMins != 0 && frequency.MaxHeadwayMins >= frequency.MinHeadwayMins
		if !hasClocks || !hasHeadway {
			return nil, nil, errors.New("frequency has invalid time/headway")
		}
		service := mask2(frequency.ServiceDay.Monday, frequency.ServiceDay.Tuesday, frequency.ServiceDay.Wednesday, frequency.ServiceDay.Thursday, frequency.ServiceDay.Friday, frequency.ServiceDay.Saturday, frequency.ServiceDay.Sunday)
		rows = append(rows, []any{uid, int16(dir), true, "", false, int16(-1), fmt.Sprint(frequency.MinHeadwayMins), fmt.Sprint(frequency.MaxHeadwayMins), frequency.StartTime, frequency.EndTime, int16(service)})
		modelRows = append(modelRows, &models.Bus_Schedule{
			IsTimetable: false, Start_Time: frequency.StartTime, End_Time: frequency.EndTime,
			MinHeadwayMinsArrivalTime: fmt.Sprint(frequency.MinHeadwayMins), MaxHeadwayMinsDepartureTime: fmt.Sprint(frequency.MaxHeadwayMins),
			ServiceDay: int32(service),
		})
	}
	return rows, modelRows, nil
}

func decodeStrictJSONArray(body []byte, target any) error {
	trimmed := bytes.TrimSpace(body)
	if len(trimmed) < 2 || trimmed[0] != '[' || trimmed[len(trimmed)-1] != ']' {
		return errors.New("payload is not a JSON array")
	}
	dec := json.NewDecoder(bytes.NewReader(trimmed))
	if err := dec.Decode(target); err != nil {
		return err
	}
	var trailing json.RawMessage
	err := dec.Decode(&trailing)
	if errors.Is(err, io.EOF) {
		return nil
	}
	if err == nil {
		return errors.New("trailing JSON value")
	}
	return _oops.Wrapf(err, "malformed trailing JSON")
}

func validClock(value string) bool {
	_, err := time.Parse("15:04", value)
	return err == nil
}

// normalizeClock accepts the two wall-clock shapes TDX publishes for a bus
// first/last time — "HH:MM" and bare "HHMM" — and returns the canonical
// "HH:MM" form. Hours run to 29 because a transit service day extends past
// midnight, so "25:30" is a real last-bus time that time.Parse("15:04")
// rejects. Callers that re-parse the value with time.Parse (rail and bus
// timetable stop times) must keep using validClock instead.
func normalizeClock(value string) (string, bool) {
	v := strings.TrimSpace(value)
	if len(v) == 4 && v[2] != ':' {
		v = v[:2] + ":" + v[2:]
	}
	if len(v) != 5 || v[2] != ':' {
		return "", false
	}
	for _, i := range [...]int{0, 1, 3, 4} {
		if v[i] < '0' || v[i] > '9' {
			return "", false
		}
	}
	h := int(v[0]-'0')*10 + int(v[1]-'0')
	m := int(v[3]-'0')*10 + int(v[4]-'0')
	if h > 29 || m > 59 {
		return "", false
	}
	return v, true
}

func validPosition(lon, lat float64) bool {
	return !math.IsNaN(lon) && !math.IsNaN(lat) && !math.IsInf(lon, 0) && !math.IsInf(lat, 0) && lon >= -180 && lon <= 180 && lat >= -90 && lat <= 90 && (lon != 0 || lat != 0)
}

func prefixID(prefix, id string) string {
	if id == "" || strings.HasPrefix(id, prefix) {
		return id
	}
	return prefix + id
}

func uidBelongsToPrefix(uid, prefix string) bool {
	return uid != "" && prefix != "" && strings.HasPrefix(uid, prefix)
}

// applySubrouteEndpoints lifts the outbound direction's endpoints onto the
// subroute, falling back to inbound for a subroute published in one direction
// only. Called again whenever a direction is pruned, so the subroute-level names
// never outlive the direction they came from.
func applySubrouteEndpoints(sub *models.BusSubroute) {
	direction := sub.Directions[0]
	if direction == nil {
		direction = sub.Directions[1]
	}
	if direction == nil {
		return
	}
	sub.DepartureStopName = direction.DepartureStopName
	sub.DestinationStopName = direction.DestinationStopName
}

// normalizeStationName strips TDX's "(市區公車)" station-name suffix. Keelung
// tags its city-bus stations with it while the InterCity dataset names the same
// physical pole without it, which breaks the same-name fold in the group-member
// upsert (bus_writer.go) and surfaces one stop twice in the nearby list.
// one known-noise suffix, not a general parenthesis strip — "(往北)",
// "(捷運站)" and friends distinguish real stops.
func normalizeStationName(name string) string {
	return strings.TrimSuffix(name, "(市區公車)")
}

func manualGroupUID(city, name string) string {
	sum := md5.Sum([]byte(name))
	return city + ":manual:" + hex.EncodeToString(sum[:])
}

func directionFor(routes map[string]*models.BusSubroute, uid string, dir uint8) *models.Direction {
	if route := routes[uid]; route != nil {
		return route.Directions[int32(dir)]
	}
	return nil
}

func appendUniqueOperator(operators []*models.BusOperator, candidate *models.BusOperator) []*models.BusOperator {
	for _, operator := range operators {
		if operator.OperatorId == candidate.OperatorId {
			return operators
		}
	}
	return append(operators, candidate)
}

func jsonSemanticEqual(a, b any) bool {
	left, err := json.Marshal(a)
	if err != nil {
		return false
	}
	right, err := json.Marshal(b)
	return err == nil && bytes.Equal(left, right)
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}
