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

// GTFSRealtimeKey returns the key holding the serialized GTFS-RT FeedMessage.
// services/functions rebuilds it on a cron; services/router reads it and returns
// the bytes verbatim. It carries a TTL longer than the rebuild period on
// purpose: if the builder stops, the key expires and the endpoint serves 503,
// so a planner falls back to the static timetable instead of a snapshot that is
// silently hours old (ADR-0019).
func GTFSRealtimeKey() string {
	return "gtfs_rt:feed"
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

// MrtTrackKey holds the live state (a marshaled models.MrtTrackState) of one
// metro alight-reminder session, keyed by its reminder/track ID. The router
// writes the initial state at CreateTrack and reads it to seed a WatchTrack
// stream; the functions tracker overwrites it each station hop (ADR-0015).
func MrtTrackKey(trackID string) string {
	return "mrt_track:state:" + trackID
}

// MrtTrackChannel publishes each new session state so an established WatchTrack
// stream receives updates after seeding from MrtTrackKey.
func MrtTrackChannel(trackID string) string {
	return "mrt_track:events:" + trackID
}

// MrtTrackPushTokenKey holds the iOS ActivityKit push token of the card showing
// one session, so the tracker can refresh that card while the app is suspended
// (ADR-0018). Session-scoped rather than device-scoped: the token is issued per
// activity and dies with the card, so it expires with the session it belongs to.
func MrtTrackPushTokenKey(trackID string) string {
	return "mrt_track:push_token:" + trackID
}

// TraDelayHashKey is the hash of per-train delay minutes, keyed by train
// number.
const TraDelayHashKey = "tra:delay"

// TraDelayAllKey is the key holding (and channel publishing) the system-wide
// TRA delay snapshot.
const TraDelayAllKey = "tra:delay:all"

// TraDelayStationKey is the hash of the station each train's delay was measured
// at, keyed by train number and written alongside TraDelayHashKey.
//
// It is a second hash rather than a richer value in the first because the app
// reads TraDelayHashKey's values as plain minutes; only the GTFS-RT feed needs
// to know where the observation was taken, and it needs it to place the delay on
// a stop rather than on the whole train.
const TraDelayStationKey = "tra:delay:station"

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

// LiveDemandKey marks one city as currently watched by at least one rider. The
// router sets it (with a TTL) whenever a live stream for that city is open;
// functions reads it to decide whether the city gets its full cadence this tick
// or the reduced one (FDPL-90). Its TTL must stay above the reduced cadence: a
// city that has gone cold publishes nothing, so the only thing that can refresh
// this key is the initial write a new subscriber makes.
func LiveDemandKey(dataset, city string) string {
	return fmt.Sprintf("live:demand:%s:%s", dataset, city)
}

// LiveColdKey marks one unwatched city as already fetched recently. Its TTL is
// the reduced cadence: while it exists the city's ticks are skipped, and its
// expiry is what lets the next tick through.
func LiveColdKey(dataset, city string) string {
	return fmt.Sprintf("live:cold:%s:%s", dataset, city)
}

// _cityUIDPrefix maps a TDX city code to the short prefix its UIDs carry. Both
// binaries need the mapping — functions to build keys per city, the router to
// resolve the city out of a UID it was asked for — so it lives here with the
// rest of the cross-binary key contract rather than being copied into each. It
// is reached only through UIDPrefixForCity and CityFromUID: exporting the map
// itself would hand every caller the ability to mutate the contract.
var _cityUIDPrefix = map[string]string{
	"Taipei": "TPE", "NewTaipei": "NWT", "Taoyuan": "TAO", "Taichung": "TXG",
	"Tainan": "TNN", "Kaohsiung": "KHH", "InterCity": "THB", "Keelung": "KEE",
	"Hsinchu": "HSZ", "HsinchuCounty": "HSQ", "MiaoliCounty": "MIA", "ChanghuaCounty": "CHA",
	"NantouCounty": "NAN", "Chiayi": "CYI", "ChiayiCounty": "CYQ", "YunlinCounty": "YUN",
	"PingtungCounty": "PIF", "YilanCounty": "ILA", "HualienCounty": "HUA", "TaitungCounty": "TTT",
	"PenghuCounty": "PEN", "KinmenCounty": "KIN", "LienchiangCounty": "LIE",
}

// _cityFromUIDPrefix is the inverse of _cityUIDPrefix.
var _cityFromUIDPrefix = func() map[string]string {
	out := make(map[string]string, len(_cityUIDPrefix))
	for city, prefix := range _cityUIDPrefix {
		out[prefix] = city
	}
	return out
}()

// UIDPrefixForCity returns the short prefix a TDX city's UIDs carry, or "" for
// a city with no mapping. Callers treat "" as a city they must not build keys
// for: a missing prefix would collapse a per-city key pattern into one matching
// every city.
func UIDPrefixForCity(city string) string {
	return _cityUIDPrefix[city]
}

// CityFromUID resolves the TDX city code from a UID that starts with a city
// prefix (bus sub-route UIDs, bike station UIDs, rail LocationCityCode). It
// returns "" for a UID too short to carry one or carrying an unknown prefix,
// which callers treat as "no city to attribute this to" rather than as an error.
func CityFromUID(uid string) string {
	if len(uid) < 3 {
		return ""
	}
	return _cityFromUIDPrefix[uid[:3]]
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

// AlertBusAlertChannel returns the channel carrying one city's bus service
// disruptions. News and disruptions stay on separate channels because each
// mirrors its own latest-payload key, and a shared key would let whichever
// topic published last decide what a new subscriber is seeded with.
func AlertBusAlertChannel(city string) string {
	return "mqtt:v2:Bus:Alert:City:" + city
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
