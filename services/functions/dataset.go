package main

// This file is the single source of truth for the raw_tdx datasets. Three
// consumers derive from datasetRegistry so the three lists can no longer drift:
//   - the ingestor fetch loop (ingestRaw) — every fetched dataset × partition,
//   - the raw-landing target map + whitelist (rawDumpTarget, rawTDXTables) in
//     main.go, which resolve a fetched URL back to its table/partition and guard
//     the SQL-injection barrier,
//   - the loader registry (loaderRegistry) in loader.go, which attaches a
//     transform to each dataset that has one, in this file's slice order.
//
// Intentional asymmetries are explicit fields, not comments the code cannot
// enforce: landOnly tables are whitelisted (their DDL may still exist on Azure)
// but never fetched; foldedInto tables are fetched and consumed by another
// dataset's multi-table loader rather than a standalone transform; loadParts
// lets a dataset load a subset of what it lands.

// landFamily classifies a dataset's TDX endpoint shape, which drives both the
// landing URL (datasetSpec.url) and the reverse URL→table resolution
// (rawDumpTarget). familyNone means the table is never fetched — whitelist and
// DDL only.
type landFamily int

const (
	_familyNone landFamily = iota
	_familyBusCity
	_familyBikeCity
	_familyMetroSystem
	_familyRailSingle
	_familyRailDate
)

// datasetSpec is one raw_tdx table's full recipe. rawTable is also its whitelist
// entry. partitions enumerates the values landed (and, unless loadParts is set,
// loaded); the loader consumes loadParts when it loads a subset of what the
// ingestor lands. family+apiSeg build the landing URL and identify the table on
// the reverse path. name is the If-Modified-Since cache identity per partition.
// loadKey names the standalone loader transform ("" when none). landOnly marks a
// whitelisted-but-never-fetched table; foldedInto names the loader that consumes
// a fetched table without a standalone transform of its own. exportOnly marks a
// table landed for the GTFS export path, which reads raw_tdx directly: it is
// fetched and consumed, but by no loader, so it carries neither loadKey nor
// foldedInto.
type datasetSpec struct {
	rawTable   string
	partCol    string
	partitions func() []string
	loadParts  func() []string
	family     landFamily
	apiSeg     string
	name       func(part string) string
	loadKey    string
	foldedInto string
	landOnly   bool
	exportOnly bool
	staleOK    bool
}

// fetched reports whether the ingestor issues requests for this dataset.
func (d datasetSpec) fetched() bool {
	return d.family != _familyNone && !d.landOnly
}

// loadPartitions returns the partitions the loader processes, defaulting to the
// landed set when the dataset loads everything it lands.
func (d datasetSpec) loadPartitions() []string {
	if d.loadParts != nil {
		return d.loadParts()
	}
	return d.partitions()
}

// url builds the landing URL for one partition of a fetched dataset.
func (d datasetSpec) url(part string) string {
	switch d.family {
	case _familyBusCity:
		if part == "InterCity" {
			return "/v2/Bus/" + d.apiSeg + "/InterCity"
		}
		return "/v2/Bus/" + d.apiSeg + "/City/" + part
	case _familyBikeCity:
		return "/v2/Bike/" + d.apiSeg + "/City/" + part
	case _familyMetroSystem:
		return "/v2/Rail/Metro/" + d.apiSeg + "/" + part
	case _familyRailSingle:
		return "/v2/Rail/" + d.apiSeg
	case _familyRailDate:
		return "/v2/Rail/" + d.apiSeg + "/TrainDate/" + part
	case _familyNone:
		// Zero value: no registry entry, so no URL.
	}
	return ""
}

// Partition enumerators shared by landing and loading so the two stages read the
// same set. allCities/bikeCities/dailyTimetableCities/singlePartition were
// loader-local closures before the registry unified them.
func allCities() []string { return _cities }

// busLoadCities is deliberately load-only: raw landing keeps the TDX fetch
// order above, while target assembly excludes unsupported Lienchiang and loads
// every municipality before InterCity. InterCity station grouping may consult
// committed municipal groups in its own target transaction.
func busLoadCities() []string {
	out := make([]string, 0, len(_cities)-1)
	for _, city := range _cities {
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

func displayStopCities() []string { return _displayStopCities }

func bikeCities() []string {
	var out []string
	for _, c := range _cities {
		if !_ingestBikeSkip[c] {
			out = append(out, c)
		}
	}
	return out
}

// dailyTimetableLoadCities is the landing set plus the cities whose partition is
// landed from somewhere other than TDX — Taipei, from Data.taipei.
func dailyTimetableLoadCities() []string {
	return append(dailyTimetableCities(), _dataTaipeiCity)
}

func dailyTimetableCities() []string {
	var out []string
	for _, c := range _cities {
		if !busDailyTimetableSkip(c) {
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
// "bus" loadKey; every other correlated table is folded into that one atomic
// city snapshot and has no standalone target transaction.
func busDataset(apiSeg, rawTable, loadKey, foldedInto string) datasetSpec {
	spec := datasetSpec{
		rawTable: rawTable, partCol: "city", partitions: allCities,
		family: _familyBusCity, apiSeg: apiSeg, name: busName(apiSeg),
		loadKey: loadKey, foldedInto: foldedInto,
	}
	if loadKey == "bus" {
		spec.loadParts = busLoadCities
	}
	return spec
}

// railSingle builds an unpartitioned TRA/THSR dataset (single TRUNCATE-lifecycle
// partition). name is constant because the endpoint carries no partition value.
func railSingle(apiSeg, rawTable, loadKey, imsName string) datasetSpec {
	return datasetSpec{
		rawTable: rawTable, partCol: "", partitions: singlePartition,
		family: _familyRailSingle, apiSeg: apiSeg,
		name:    func(string) string { return imsName },
		loadKey: loadKey,
	}
}

// railSingleExport and metroExport build the GTFS-export datasets: landed for
// the feed builder, which reads raw_tdx directly, and therefore bound to no
// loader transform. They are separate constructors rather than a flag on the
// existing ones so an export dataset can never acquire a loadKey by accident.
func railSingleExport(apiSeg, rawTable, imsName string) datasetSpec {
	spec := railSingle(apiSeg, rawTable, "", imsName)
	spec.exportOnly = true
	return spec
}

func metroExport(apiSeg, rawTable, imsPrefix string, systems func() []string) datasetSpec {
	return datasetSpec{
		rawTable: rawTable, partCol: "system",
		partitions: systems,
		family:     _familyMetroSystem, apiSeg: apiSeg,
		name:       func(part string) string { return imsPrefix + part },
		exportOnly: true,
	}
}

// datasetRegistry is the ordered dataset table. Slice order is the load order:
// filtering to loadKey-bearing entries yields the loaderRegistry order. The
// bus_route owns the one atomic bus snapshot load. Operator and the other seven
// correlated inputs remain adjacent raw landing datasets but are folded into it.
func datasetRegistry() []datasetSpec {
	return []datasetSpec{
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
		{rawTable: "bus_displaystopofroute", partCol: "city", partitions: displayStopCities,
			family: _familyBusCity, apiSeg: "DisplayStopOfRoute",
			name: busName("DisplayStopOfRoute"), loadKey: "bus_displaystop"},
		// Landed and loaded for the same city set: TDX answers HTTP 400 (not an
		// empty payload) for the cities in busDailyTimetableSkip, so landing them
		// only produced a nightly ingest failure for data no loader would read.
		{rawTable: "bus_dailytimetable", partCol: "city", partitions: dailyTimetableCities,
			loadParts: dailyTimetableLoadCities, family: _familyBusCity, apiSeg: "DailyTimeTable",
			name: busName("DailyTimeTable"), loadKey: "bus_dailytimetable"},
		// Bus/Stop is intentionally absent from the fetch and reverse maps: it is
		// never fetched and never loaded. The whitelist/DDL entry is kept because
		// the table may already exist on Azure.
		{rawTable: "bus_stop", landOnly: true},
		{rawTable: "bike_station", partCol: "city", partitions: bikeCities,
			family: _familyBikeCity, apiSeg: "Station",
			name: func(p string) string { return "bike_" + p }, loadKey: "bike"},
		{rawTable: "metro_station", partCol: "system", partitions: func() []string { return _ingestMetroStationSystems },
			family: _familyMetroSystem, apiSeg: "Station",
			name: func(p string) string { return "metro_station_" + p }, loadKey: "mrt_station"},
		{rawTable: "metro_schedule", partCol: "system", partitions: func() []string { return _ingestMetroFirstLast },
			family: _familyMetroSystem, apiSeg: "FirstLastTimetable",
			name: func(p string) string { return "metro_fl_" + p }, loadKey: "mrt_firstlast", staleOK: true},
		{rawTable: "metro_odfare", partCol: "system", partitions: func() []string { return _ingestMetroODFare },
			family: _familyMetroSystem, apiSeg: "ODFare",
			name: func(p string) string { return "metro_od_" + p }, loadKey: "mrt_odfare"},
		// Drives both metro travel-graph loaders. metro_linetransfer is landed for
		// fewer systems, which is not a constraint here: readDatasetJSON returns an
		// empty array for an unlanded partition, and no interchange is the correct
		// graph for a single-line system.
		{rawTable: "metro_s2straveltime", partCol: "system", partitions: func() []string { return _ingestMetroS2STravelTime },
			family: _familyMetroSystem, apiSeg: "S2STravelTime",
			name: func(p string) string { return "metro_s2s_" + p }, loadKey: "mrt_traveltime"},
		{rawTable: "metro_linetransfer", partCol: "system", partitions: func() []string { return _ingestMetroLineTransfer },
			family: _familyMetroSystem, apiSeg: "LineTransfer",
			name: func(p string) string { return "metro_transfer_" + p }, foldedInto: "mrt_traveltime"},
		railSingle("TRA/Station", "tra_station", "tra_station", "tra_station"),
		railSingle("THSR/Station", "thsr_station", "thsr_station", "thsr_station"),
		railSingle("TRA/ODFare", "tra_odfare", "tra_fare", "tra_odfare"),
		railSingle("THSR/ODFare", "thsr_odfare", "thsr_fare", "thsr_odfare"),
		railSingle("TRA/Shape", "tra_shape", "tra_shape", "tra_shape"),
		railSingle("THSR/Shape", "thsr_shape", "thsr_shape", "thsr_shape"),
		{rawTable: "metro_shape", partCol: "system", partitions: func() []string { return _ingestMetroStationSystems },
			family: _familyMetroSystem, apiSeg: "Shape",
			name: func(p string) string { return "metro_shape_" + p }, loadKey: "metro_shape"},
		{rawTable: "tra_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(60) },
			family: _familyRailDate, apiSeg: "TRA/DailyTimetable",
			name: func(p string) string { return "tra_daily_" + p }, loadKey: "tra_timetable"},
		{rawTable: "thsr_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(45) },
			family: _familyRailDate, apiSeg: "THSR/DailyTimetable",
			name: func(p string) string { return "thsr_daily_" + p }, loadKey: "thsr_timetable"},
		// TRA/TrainType resolves on the reverse path (its DDL/whitelist entry is
		// kept) but is never fetched: nothing loads raw_tdx.tra_traintype, and
		// train-type data arrives inside the daily-timetable payloads.
		{rawTable: "tra_traintype", family: _familyRailSingle, apiSeg: "TRA/TrainType", landOnly: true},

		// GTFS export datasets. These land for the feed builder only — no loader
		// reads them, so they appear after the load-ordered entries above and
		// carry exportOnly. Metro/Route is the route source rather than
		// Metro/Line: branches and short-turn services (Xinbeitou, Xiaobitan, the
		// Daan-Beitou short working) exist only at the Route level, so building
		// routes from Line would drop them. Metro/Line is landed alongside it
		// purely for LineColor, which Route does not carry.
		metroExport("Route", "metro_route", "metro_route_", func() []string { return _metroSystemsAll }),
		metroExport("StationOfRoute", "metro_stationofroute", "metro_sor_", func() []string { return _metroSystemsAll }),
		metroExport("Line", "metro_line", "metro_line_", func() []string { return _metroSystemsAll }),
		metroExport("Frequency", "metro_frequency", "metro_freq_", func() []string { return _ingestMetroFrequency }),
		metroExport("StationExit", "metro_stationexit", "metro_exit_", func() []string { return _ingestMetroExit }),
		railSingleExport("THSR/StationExit", "thsr_stationexit", "thsr_stationexit"),
		railSingleExport("Operator", "rail_operator", "rail_operator"),
	}
}

// famSeg keys the reverse index: (family, endpoint segment) → dataset. The
// segment is family-scoped so bus "Station" and metro "Station" do not collide.
type famSeg struct {
	family landFamily
	seg    string
}

// _rawTargetIndex resolves a parsed landing URL back to its dataset. It includes
// every reverse-mappable dataset (family != familyNone), so landOnly-but-mappable
// tables like tra_traintype still resolve while the unfetched bus_stop
// (familyNone) does not — matching the legacy rawDumpTarget maps exactly.
var _rawTargetIndex = buildRawTargetIndex()

func buildRawTargetIndex() map[famSeg]datasetSpec {
	m := make(map[famSeg]datasetSpec)
	for _, d := range datasetRegistry() {
		if d.family == _familyNone {
			continue
		}
		m[famSeg{d.family, d.apiSeg}] = d
	}
	return m
}
