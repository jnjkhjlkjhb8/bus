package shared

import (
	"fmt"
	"strings"
)

// This file is the Redis key contract between the two binaries: functions
// writes these keys and channels, router reads them (docs/redis.md describes
// the payloads). Constructing any cross-binary key inline instead of through
// these helpers reintroduces the silent-mismatch class of bug this file
// removes.

// BusRouteEtaKey returns the key holding (and channel publishing) a bus
// route's live ETA snapshot. The UID must already be canonical.
func BusRouteEtaKey(subRouteUID string) string {
	return "bus_eta_route:" + subRouteUID
}

// BusRouteEtaPattern matches every bus route ETA key whose canonical UID
// starts with uidPrefix (a city's route-UID prefix, e.g. "TPE").
func BusRouteEtaPattern(uidPrefix string) string {
	return "bus_eta_route:" + uidPrefix + "*"
}

// BusStationEtaKey returns the key holding (and channel publishing) a station
// group's live bus arrivals.
func BusStationEtaKey(city, groupUID string) string {
	return fmt.Sprintf("bus_eta_station:%s:%s", city, groupUID)
}

// BusStationEtaPattern matches every station-group ETA key in one city.
func BusStationEtaPattern(city string) string {
	return fmt.Sprintf("bus_eta_station:%s:*", city)
}

// BusETARawKey holds the last durably decoded TDX ETA feed for a city.
func BusETARawKey(city string) string {
	return "bus:raw:eta:" + city
}

// BusPositionRawKey holds the last durably decoded TDX position feed for a city.
func BusPositionRawKey(city string) string {
	return "bus:raw:position:" + city
}

// BusStaticGenerationKey is the durable cross-process version of one city's
// static stop map. The loader increments it only after the PostgreSQL snapshot
// commits; realtime workers compare it before reusing their local cache.
func BusStaticGenerationKey(city string) string {
	return "bus:static:generation:" + city
}

// BusStaticGenerationChannel optionally wakes online consumers after a static
// commit. Correctness never depends on Pub/Sub: the durable generation key is
// checked on every realtime refresh, so a disconnected worker catches up.
func BusStaticGenerationChannel(city string) string {
	return "bus:static:generation:changed:" + city
}

// BusDailyTimetableKey returns the key holding a canonical subroute's daily
// timetable, written by the 03:30 load.
func BusDailyTimetableKey(subRouteUID string) string {
	return "bus_daily_timetable:" + subRouteUID
}

// MrtLiveKey returns the key holding one metro arrival. Destination is part of
// the identity because a station can have simultaneous arrivals on the same
// line in opposite directions.
func MrtLiveKey(system, stationID, lineID, destinationStationID string) string {
	return fmt.Sprintf("mrt_live:%s:%s:%s:%s", system, stationID, lineID, destinationStationID)
}

// MrtLiveChannel returns the channel publishing a metro station's arrivals
// (all lines share the station channel).
func MrtLiveChannel(system, stationID string) string {
	return fmt.Sprintf("mrt_live:%s:%s", system, stationID)
}

// MrtLiveSeedPattern matches every per-line key under one station, used to
// seed a new subscriber before live updates begin.
func MrtLiveSeedPattern(system, stationID string) string {
	return MrtLiveChannel(system, stationID) + ":*"
}

// MrtLivePattern matches every metro live-arrival key and station channel.
func MrtLivePattern() string {
	return "mrt_live:*"
}

// TraDelayHashKey is the hash of per-train delay minutes, keyed by train
// number.
const TraDelayHashKey = "tra:delay"

// TraDelayAllKey is the key holding (and channel publishing) the system-wide
// TRA delay snapshot.
const TraDelayAllKey = "tra:delay:all"

// TraDelayTrainChannel returns the per-train delay key/channel written by the
// realtime TRA job and consumed by the router's Tra_DetainService.
func TraDelayTrainChannel(trainNo string) string {
	return "tra:delay:" + trainNo
}

// BikeAvailabilityKey returns the key holding (and channel publishing) a bike
// station's live availability.
func BikeAvailabilityKey(stationUID string) string {
	return "bike_availability:" + stationUID
}

// LiveOwnedKeysKey stores the exact data keys last written by one live
// partition. A partition 304 uses the set to refresh only its own TTLs.
func LiveOwnedKeysKey(dataset, partition string) string {
	return fmt.Sprintf("live:owned:%s:%s", dataset, partition)
}

// WeatherKey returns the key holding one city's cached weather snapshot. It is a
// cross-module contract: weatherSync writes it (60-minute TTL) and the bus ETA
// path reads it for prediction features, so both sides construct it here.
func WeatherKey(city string) string {
	return "weather:" + city
}

// MQTTChannel derives the Redis key/channel caching an MQTT message from its
// topic: "mqtt:" plus the topic with path separators flattened to colons. The
// alert channel constructors below must agree with this derivation.
func MQTTChannel(topic string) string {
	return "mqtt:" + strings.ReplaceAll(topic, "/", ":")
}

// AlertBusNewsChannel returns the channel carrying one city's bus service
// news. An empty city subscribes to a channel that never receives messages.
func AlertBusNewsChannel(city string) string {
	return "mqtt:v2:Bus:News:City:" + city
}

// AlertMetroChannel returns the channel carrying one metro system's alerts.
func AlertMetroChannel(system string) string {
	return "mqtt:v2:Rail:Metro:Alert:" + system
}

// AlertTraChannel is the channel carrying all TRA alerts.
const AlertTraChannel = "mqtt:v3:Rail:TRA:Alert"

// AlertThsrChannel is the channel carrying all THSR alerts.
const AlertThsrChannel = "mqtt:v2:Rail:THSR:AlertInfo"

// ThsrSeatsKey returns the key holding (and channel publishing) one THSR train's
// available-seat snapshot for a date. functions/router write it via the realtime
// seat refresh; the router's AvailableSeats stream reads it back by glob.
func ThsrSeatsKey(date, trainNo string) string {
	return fmt.Sprintf("thsr_seats:%s:%s", date, trainNo)
}

// ThsrSeatsPattern matches every THSR seat key (and channel) for one date, used
// by the AvailableSeats stream's SCAN seed and PSubscribe.
func ThsrSeatsPattern(date string) string {
	return fmt.Sprintf("thsr_seats:%s:*", date)
}

// TDX credential keys. Redis is one DB namespaced by key prefix: the auth token
// lives under the namespaced shared:* key, with the legacy bare key kept as a
// read/delete fallback during the transition off it.
const (
	// TDXTokenKey is the namespaced TDX OAuth bearer-token cache key.
	TDXTokenKey = "shared:tdx:access_token"
	// TDXTokenKeyLegacy is the pre-namespacing token key, still read as a
	// fallback and deleted alongside TDXTokenKey on a 401 re-auth.
	TDXTokenKeyLegacy = "TDX_Token"
)

// TDXRawIMSKey returns the namespaced If-Modified-Since marker key for a raw_tdx
// landing target (ingestor path).
func TDXRawIMSKey(name string) string {
	return "shared:raw:last_modified:" + name
}

// TDXLegacyIMSKey returns the legacy (bare) If-Modified-Since marker key used by
// the prod transform path and the router's realtime THSR-seat fetch.
func TDXLegacyIMSKey(name string) string {
	return "LastTimeGet_" + name
}
