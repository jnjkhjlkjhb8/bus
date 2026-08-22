// Package dataset is the catalogue of every TDX dataset the pipeline touches:
// which raw table it lands in, how it partitions, what its IMS cache identity
// is, and which loader consumes it. The ingestor, the loader and the GTFS
// export all read the same entries, so a dataset cannot be landed without a
// declared target or loaded without a declared source.
package dataset

import (
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/busmodel"
)

// This file is the single source of truth for the raw_tdx datasets. Three
// consumers derive from Registry so the three lists can no longer drift:
//   - the ingestor fetch loop (ingestRaw) — every fetched dataset × partition,
//   - the raw-landing target map + whitelist (rawDumpTarget, rawTDXTables) in
//     main.go, which resolve a fetched URL back to its table/partition and guard
//     the SQL-injection barrier,
//   - the loader registry (loaderRegistry) in loader.go, which attaches a
//     transform to each dataset that has one, in this file's slice order.
//
// Intentional asymmetries are explicit fields, not comments the code cannot
// enforce: LandOnly tables are whitelisted (their DDL may still exist on Azure)
// but never fetched; FoldedInto tables are fetched and consumed by another
// dataset's multi-table loader rather than a standalone transform; LoadParts
// lets a dataset load a subset of what it lands.

// LandFamily classifies a dataset's TDX endpoint shape, which drives both the
// landing URL (Spec.url) and the reverse URL→table resolution
// (rawDumpTarget). familyNone means the table is never fetched — whitelist and
// DDL only.
type LandFamily int

const (
	FamilyNone LandFamily = iota
	FamilyBusCity
	FamilyBikeCity
	FamilyMetroSystem
	FamilyRailSingle
	FamilyRailDate
)

// Spec is one raw_tdx table's full recipe. RawTable is also its whitelist
// entry. Partitions enumerates the values landed (and, unless LoadParts is set,
// loaded); the loader consumes LoadParts when it loads a subset of what the
// ingestor lands. family+APISeg build the landing URL and identify the table on
// the reverse path. name is the If-Modified-Since cache identity per partition.
// LoadKey names the standalone loader transform ("" when none). LandOnly marks a
// whitelisted-but-never-fetched table; FoldedInto names the loader that consumes
// a fetched table without a standalone transform of its own. ExportOnly marks a
// table landed for the GTFS export path, which reads raw_tdx directly: it is
// fetched and consumed, but by no loader, so it carries neither LoadKey nor
// FoldedInto.
type Spec struct {
	RawTable   string
	PartCol    string
	Partitions func() []string
	LoadParts  func() []string
	Family     LandFamily
	APISeg     string
	Name       func(part string) string
	LoadKey    string
	FoldedInto string
	LandOnly   bool
	ExportOnly bool
	StaleOK    bool
}

// fetched reports whether the ingestor issues requests for this dataset.
func (d Spec) Fetched() bool {
	return d.Family != FamilyNone && !d.LandOnly
}

// loadPartitions returns the Partitions the loader processes, defaulting to the
// landed set when the dataset loads everything it lands.
func (d Spec) LoadPartitions() []string {
	if d.LoadParts != nil {
		return d.LoadParts()
	}
	return d.Partitions()
}

// url builds the landing URL for one partition of a fetched dataset.
func (d Spec) URL(part string) string {
	switch d.Family {
	case FamilyBusCity:
		if part == "InterCity" {
			return "/v2/Bus/" + d.APISeg + "/InterCity"
		}
		return "/v2/Bus/" + d.APISeg + "/City/" + part
	case FamilyBikeCity:
		return "/v2/Bike/" + d.APISeg + "/City/" + part
	case FamilyMetroSystem:
		return "/v2/Rail/Metro/" + d.APISeg + "/" + part
	case FamilyRailSingle:
		return "/v2/Rail/" + d.APISeg
	case FamilyRailDate:
		return "/v2/Rail/" + d.APISeg + "/TrainDate/" + part
	case FamilyNone:
		// Zero value: no registry entry, so no URL.
	}
	return ""
}

// Partition enumerators shared by landing and loading so the two stages read the
// same set. AllCities/BikeCities/DailyTimetableCities/singlePartition were
// loader-local closures before the registry unified them.
func AllCities() []string { return busmodel.Cities }

// BusLoadCities is deliberately load-only: raw landing keeps the TDX fetch
// order above, while target assembly excludes unsupported Lienchiang and loads
// every municipality before InterCity. InterCity station grouping may consult
// committed municipal groups in its own target transaction.
func BusLoadCities() []string {
	out := make([]string, 0, len(busmodel.Cities)-1)
	for _, city := range busmodel.Cities {
		if city == "LienchiangCounty" || city == "InterCity" {
			continue
		}
		out = append(out, city)
	}
	return append(out, "InterCity")
}

// _displayStopCities is the whole set TDX serves Bus/DisplayStopOfRoute for.
// Every other city answers HTTP 400 naming these five, and the InterCity
// endpoint answers 404 on both v2 and v3 (verified 2026-08-09). Only the cities
// that define a linearised display list have one, which is the point of the
// dataset: it exists where a route's branches need folding into one page.
var _displayStopCities = []string{"Taipei", "NewTaipei", "Taoyuan", "Taichung", "Tainan"}

func DisplayStopCities() []string { return _displayStopCities }

func BikeCities() []string {
	var out []string
	for _, c := range busmodel.Cities {
		if !BikeSkip[c] {
			out = append(out, c)
		}
	}
	return out
}

// DailyTimetableLoadCities is the landing set plus the cities whose partition is
// landed from somewhere other than TDX — Taipei, from Data.taipei.
func DailyTimetableLoadCities() []string {
	return append(DailyTimetableCities(), DataTaipeiCity)
}

func DailyTimetableCities() []string {
	var out []string
	for _, c := range busmodel.Cities {
		if !BusDailyTimetableSkip(c) {
			out = append(out, c)
		}
	}
	return out
}

func singlePartition() []string { return []string{""} }

// busName builds a bus dataset's per-partition IMS cache identity ("bus_"+API+
// city), matching the legacy ingestor names byte for byte.
func busName(apiSeg string) func(string) string {
	return func(p string) string { return "bus_" + apiSeg + p }
}

// busDataset builds one per-city bus static dataset. Only bus_route carries the
// "bus" LoadKey; every other correlated table is folded into that one atomic
// city snapshot and has no standalone target transaction.
func busDataset(apiSeg, rawTable, loadKey, foldedInto string) Spec {
	spec := Spec{
		RawTable: rawTable, PartCol: "city", Partitions: AllCities,
		Family: FamilyBusCity, APISeg: apiSeg, Name: busName(apiSeg),
		LoadKey: loadKey, FoldedInto: foldedInto,
	}
	if loadKey == "bus" {
		spec.LoadParts = BusLoadCities
	}
	return spec
}

// railSingle builds an unpartitioned TRA/THSR dataset (single TRUNCATE-lifecycle
// partition). name is constant because the endpoint carries no partition value.
func railSingle(apiSeg, rawTable, loadKey, imsName string) Spec {
	return Spec{
		RawTable: rawTable, PartCol: "", Partitions: singlePartition,
		Family: FamilyRailSingle, APISeg: apiSeg,
		Name:    func(string) string { return imsName },
		LoadKey: loadKey,
	}
}

// railSingleExport and metroExport build the GTFS-export datasets: landed for
// the feed builder, which reads raw_tdx directly, and therefore bound to no
// loader transform. They are separate constructors rather than a flag on the
// existing ones so an export dataset can never acquire a LoadKey by accident.
func railSingleExport(apiSeg, rawTable, imsName string) Spec {
	spec := railSingle(apiSeg, rawTable, "", imsName)
	spec.ExportOnly = true
	return spec
}

func metroExport(apiSeg, rawTable, imsPrefix string, systems func() []string) Spec {
	return Spec{
		RawTable: rawTable, PartCol: "system",
		Partitions: systems,
		Family:     FamilyMetroSystem, APISeg: apiSeg,
		Name:       func(part string) string { return imsPrefix + part },
		ExportOnly: true,
	}
}

// Registry is the ordered dataset table. Slice order is the load order:
// filtering to LoadKey-bearing entries yields the loaderRegistry order. The
// bus_route owns the one atomic bus snapshot load. Operator and the other seven
// correlated inputs remain adjacent raw landing datasets but are folded into it.
func Registry() []Spec {
	return []Spec{
		busDataset("Operator", "bus_operator", "", "bus"),
		busDataset("Route", "bus_route", "bus", ""),
		busDataset("StopOfRoute", "bus_stopofroute", "", "bus"),
		busDataset("Shape", "bus_shape", "", "bus"),
		busDataset("Schedule", "bus_schedule", "", "bus"),
		busDataset("Station", "bus_station", "", "bus"),
		busDataset("StationGroup", "bus_stationgroup", "", "bus"),
		busDataset("RouteFare", "bus_routefare", "", "bus"),
		// The route-level linearised stop list (FDPL-84). Landed for the five
		// cities TDX serves it for, and loaded by its own transform rather than
		// folded into the bus city snapshot — see loadBusDisplayStops.
		{RawTable: "bus_displaystopofroute", PartCol: "city", Partitions: DisplayStopCities,
			Family: FamilyBusCity, APISeg: "DisplayStopOfRoute",
			Name: busName("DisplayStopOfRoute"), LoadKey: "bus_displaystop"},
		// Landed and loaded for the same city set: TDX answers HTTP 400 (not an
		// empty payload) for the cities in BusDailyTimetableSkip, so landing them
		// only produced a nightly ingest failure for data no loader would read.
		{RawTable: "bus_dailytimetable", PartCol: "city", Partitions: DailyTimetableCities,
			LoadParts: DailyTimetableLoadCities, Family: FamilyBusCity, APISeg: "DailyTimeTable",
			Name: busName("DailyTimeTable"), LoadKey: "bus_dailytimetable"},
		// Bus/Stop is intentionally absent from the fetch and reverse maps: it is
		// never fetched and never loaded. The whitelist/DDL entry is kept because
		// the table may already exist on Azure.
		{RawTable: "bus_stop", LandOnly: true},
		{RawTable: "bike_station", PartCol: "city", Partitions: BikeCities,
			Family: FamilyBikeCity, APISeg: "Station",
			Name: func(p string) string { return "bike_" + p }, LoadKey: "bike"},
		{RawTable: "metro_station", PartCol: "system", Partitions: func() []string { return MetroStationSystems },
			Family: FamilyMetroSystem, APISeg: "Station",
			Name: func(p string) string { return "metro_station_" + p }, LoadKey: "mrt_station"},
		{RawTable: "metro_schedule", PartCol: "system", Partitions: func() []string { return MetroFirstLast },
			Family: FamilyMetroSystem, APISeg: "FirstLastTimetable",
			Name: func(p string) string { return "metro_fl_" + p }, LoadKey: "mrt_firstlast", StaleOK: true},
		{RawTable: "metro_odfare", PartCol: "system", Partitions: func() []string { return MetroODFare },
			Family: FamilyMetroSystem, APISeg: "ODFare",
			Name: func(p string) string { return "metro_od_" + p }, LoadKey: "mrt_odfare"},
		// Drives both metro travel-graph loaders. metro_linetransfer is landed for
		// fewer systems, which is not a constraint here: readDatasetJSON returns an
		// empty array for an unlanded partition, and no interchange is the correct
		// graph for a single-line system.
		{RawTable: "metro_s2straveltime", PartCol: "system", Partitions: func() []string { return MetroS2STravelTime },
			Family: FamilyMetroSystem, APISeg: "S2STravelTime",
			Name: func(p string) string { return "metro_s2s_" + p }, LoadKey: "mrt_traveltime"},
		{RawTable: "metro_linetransfer", PartCol: "system", Partitions: func() []string { return MetroLineTransfer },
			Family: FamilyMetroSystem, APISeg: "LineTransfer",
			Name: func(p string) string { return "metro_transfer_" + p }, FoldedInto: "mrt_traveltime"},
		railSingle("TRA/Station", "tra_station", "tra_station", "tra_station"),
		railSingle("THSR/Station", "thsr_station", "thsr_station", "thsr_station"),
		railSingle("TRA/ODFare", "tra_odfare", "tra_fare", "tra_odfare"),
		railSingle("THSR/ODFare", "thsr_odfare", "thsr_fare", "thsr_odfare"),
		railSingle("TRA/Shape", "tra_shape", "tra_shape", "tra_shape"),
		railSingle("THSR/Shape", "thsr_shape", "thsr_shape", "thsr_shape"),
		{RawTable: "metro_shape", PartCol: "system", Partitions: func() []string { return MetroStationSystems },
			Family: FamilyMetroSystem, APISeg: "Shape",
			Name: func(p string) string { return "metro_shape_" + p }, LoadKey: "metro_shape"},
		{RawTable: "tra_dailytimetable", PartCol: "traindate", Partitions: func() []string { return RailDateWindow(60) },
			Family: FamilyRailDate, APISeg: "TRA/DailyTimetable",
			Name: func(p string) string { return "tra_daily_" + p }, LoadKey: "tra_timetable"},
		{RawTable: "thsr_dailytimetable", PartCol: "traindate", Partitions: func() []string { return RailDateWindow(45) },
			Family: FamilyRailDate, APISeg: "THSR/DailyTimetable",
			Name: func(p string) string { return "thsr_daily_" + p }, LoadKey: "thsr_timetable"},
		// TRA/TrainType resolves on the reverse path (its DDL/whitelist entry is
		// kept) but is never fetched: nothing loads raw_tdx.tra_traintype, and
		// train-type data arrives inside the daily-timetable payloads.
		{RawTable: "tra_traintype", Family: FamilyRailSingle, APISeg: "TRA/TrainType", LandOnly: true},

		// GTFS export datasets. These land for the feed builder only — no loader
		// reads them, so they appear after the load-ordered entries above and
		// carry ExportOnly. Metro/Route is the route source rather than
		// Metro/Line: branches and short-turn services (Xinbeitou, Xiaobitan, the
		// Daan-Beitou short working) exist only at the Route level, so building
		// routes from Line would drop them. Metro/Line is landed alongside it
		// purely for LineColor, which Route does not carry.
		metroExport("Route", "metro_route", "metro_route_", func() []string { return MetroSystemsAll }),
		metroExport("StationOfRoute", "metro_stationofroute", "metro_sor_", func() []string { return MetroSystemsAll }),
		metroExport("Line", "metro_line", "metro_line_", func() []string { return MetroSystemsAll }),
		metroExport("Frequency", "metro_frequency", "metro_freq_", func() []string { return MetroFrequency }),
		metroExport("StationExit", "metro_stationexit", "metro_exit_", func() []string { return MetroExit }),
		railSingleExport("THSR/StationExit", "thsr_stationexit", "thsr_stationexit"),
		railSingleExport("Operator", "rail_operator", "rail_operator"),
	}
}

// FamSeg keys the reverse index: (family, endpoint segment) → dataset. The
// segment is family-scoped so bus "Station" and metro "Station" do not collide.
type FamSeg struct {
	Family LandFamily
	Seg    string
}

// RawTargetIndex resolves a parsed landing URL back to its dataset. It includes
// every reverse-mappable dataset (family != familyNone), so LandOnly-but-mappable
// tables like tra_traintype still resolve while the unfetched bus_stop
// (familyNone) does not — matching the legacy rawDumpTarget maps exactly.
var RawTargetIndex = buildRawTargetIndex()

func buildRawTargetIndex() map[FamSeg]Spec {
	m := make(map[FamSeg]Spec)
	for _, d := range Registry() {
		if d.Family == FamilyNone {
			continue
		}
		m[FamSeg{d.Family, d.APISeg}] = d
	}
	return m
}

// cities with no public bike-share feed.
var BikeSkip = map[string]bool{
	"Keelung": true, "HsinchuCounty": true, "NantouCounty": true,
	"YilanCounty": true, "PenghuCounty": true, "KinmenCounty": true,
	"LienchiangCounty": true, "InterCity": true, "HualienCounty": true,
}

// BusDailyTimetableSkip lists cities whose daily-timetable feed TDX does not
// serve, so the TDX landing Partitions skip them.
func BusDailyTimetableSkip(city string) bool {
	return city == "Taipei" || city == "NewTaipei" || city == "Tainan" ||
		city == "KinmenCounty" || city == "LienchiangCounty"
}

// RailDateWindow returns today..today+n as YYYY-MM-DD strings, matching the
// ingestor's landing window (day 0 = today) so every landed timetable partition
// has a loader partition.
func RailDateWindow(n int) []string {
	today := time.Now()
	out := make([]string, 0, n+1)
	for i := 0; i <= n; i++ {
		out = append(out, today.AddDate(0, 0, i).Format(time.DateOnly))
	}
	return out
}

// DataTaipeiCity is the only city GetSpecTimeTable — the daily timetable feed
// landed in datataipei_static.go — can join to; New Taipei's blob does not
// publish that endpoint at all. The live feeds in this file are broader and
// use dataTaipeiDynamicCities instead.
const DataTaipeiCity = "Taipei"

// Metro system codes to land per endpoint. Each list is every system its
// endpoint accepts, so coverage is as wide as TDX allows; the lists differ only
// because TDX publishes a different system set per dataset, and answers an
// unsupported system with HTTP 400 rather than an empty payload.
//
// The lists are the endpoints' own answers, not a guess: TDX enumerates every
// accepted value in the 400 body, so one request with an invalid system returns
// the authoritative set. Re-probe that way when a system is added:
//
//	GET /v2/Rail/Metro/<Endpoint>/ZZZZ
var (
	// MetroSystemsAll is every rail system TDX serves. Station, Shape, ODFare,
	// Route, StationOfRoute and Line all accept the full set.
	MetroSystemsAll = []string{
		"TRTC", "KRTC", "TYMC", "KLRT", "NTDLRT", "NTALRT", "TMRT", "NTMC", "TRTCMG",
	}

	MetroStationSystems = MetroSystemsAll
	MetroODFare         = MetroSystemsAll
	// FirstLastTimetable omits the two newest light-rail lines.
	MetroFirstLast = []string{"TRTC", "KRTC", "TYMC", "KLRT", "TMRT", "NTMC", "TRTCMG"}
	// S2STravelTime and LineTransfer feed the travel graph. Both consumers
	// (mrt_traveltime, mrt_adjacency) run over the S2STravelTime set; a system
	// with no LineTransfer partition reads as an empty array, which is the right
	// answer for a single-line system that has no line-to-line interchange.
	MetroS2STravelTime = []string{"TRTC", "KRTC", "TYMC", "KLRT", "TMRT", "NTMC"}
	// LineTransfer is narrower than the four systems TDX accepts, because TYMC
	// serves an empty array and sends no Last-Modified header with it. The
	// landing path requires a marker (raw_land.go), so that partition fails every
	// run and never self-heals — it cannot record the state that would let a
	// later 304 pass. Airport MRT is single-line and genuinely has no interchange,
	// so there is nothing to lose by not asking. Restore TYMC here if it ever
	// gains a second line.
	MetroLineTransfer = []string{"TRTC", "KRTC", "NTMC"}
	// The GTFS export endpoints. Frequency is narrower than the systems TDX
	// serves it for because it is only what the feed can express: TRTCMG (Maokong
	// Gondola) has routes, stations and exits but no service data at all, so the
	// builder skips it (FDPL-6).
	//
	// Metro/StationTimeTable used to be landed alongside these and is not any
	// more. Nothing ever read it: the metro half of the feed is built from routes,
	// stations and headways, so a per-station timetable had no consumer, and the
	// real per-train times are coming from TDX's published GTFS instead
	// (FDPL-69).
	MetroFrequency = []string{"TRTC", "KRTC", "TYMC", "TMRT", "NTMC"}
	MetroExit      = []string{"TRTC", "KRTC", "TYMC", "TMRT", "NTMC", "TRTCMG"}
)
