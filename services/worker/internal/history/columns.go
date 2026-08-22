package history

// BusStopEventCols is the archive table's column order; see
// migrations/mysql/2026-08-09-bus-stop-event.sql. The natural key
// (plate, stop, event type, event time) is unique there, so re-reading the same
// A2 record on the next tick is an INSERT IGNORE no-op rather than a duplicate.
var BusStopEventCols = []string{
	"plate_numb", "city", "sub_route_uid", "direction", "stop_uid", "stop_sequence",
	"event_type", "event_time", "trip_start_time", "trip_start_time_type", "recorded_at",
}
