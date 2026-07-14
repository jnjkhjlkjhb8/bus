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
	familyNone landFamily = iota
	familyBusCity
	familyBikeCity
	familyMetroSystem
	familyRailSingle
	familyRailDate
)

// datasetSpec is one raw_tdx table's full recipe. rawTable is also its whitelist
// entry. partitions enumerates the values landed (and, unless loadParts is set,
// loaded); the loader consumes loadParts when it loads a subset of what the
// ingestor lands. family+apiSeg build the landing URL and identify the table on
// the reverse path. name is the If-Modified-Since cache identity per partition.
// loadKey names the standalone loader transform ("" when none). landOnly marks a
// whitelisted-but-never-fetched table; foldedInto names the loader that consumes
// a fetched table without a standalone transform of its own.
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
	staleOK bool
}

// fetched reports whether the ingestor issues requests for this dataset.
func (d datasetSpec) fetched() bool {
	return d.family != familyNone && !d.landOnly
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
	case familyBusCity:
		if part == "InterCity" {
			return "/v2/Bus/" + d.apiSeg + "/InterCity"
		}
		return "/v2/Bus/" + d.apiSeg + "/City/" + part
	case familyBikeCity:
		return "/v2/Bike/" + d.apiSeg + "/City/" + part
	case familyMetroSystem:
		return "/v2/Rail/Metro/" + d.apiSeg + "/" + part
	case familyRailSingle:
		return "/v2/Rail/" + d.apiSeg
	case familyRailDate:
		return "/v2/Rail/" + d.apiSeg + "/TrainDate/" + part
	}
	return ""
}

// Partition enumerators shared by landing and loading so the two stages read the
// same set. allCities/bikeCities/dailyTimetableCities/singlePartition were
// loader-local closures before the registry unified them.
func allCities() []string { return cities }

func bikeCities() []string {
	var out []string
	for _, c := range cities {
		if !ingestBikeSkip[c] {
			out = append(out, c)
		}
	}
	return out
}

func dailyTimetableCities() []string {
	var out []string
	for _, c := range cities {
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

// busDataset builds one per-city bus static dataset. loadKey is set on the
// datasets with a standalone loader (bus_route→"bus", bus_operator); foldedInto
// is set on the tables the multi-table bus assembly reads directly.
func busDataset(apiSeg, rawTable, loadKey, foldedInto string) datasetSpec {
	return datasetSpec{
		rawTable: rawTable, partCol: "city", partitions: allCities,
		family: familyBusCity, apiSeg: apiSeg, name: busName(apiSeg),
		loadKey: loadKey, foldedInto: foldedInto,
	}
}

// railSingle builds an unpartitioned TRA/THSR dataset (single TRUNCATE-lifecycle
// partition). name is constant because the endpoint carries no partition value.
func railSingle(apiSeg, rawTable, loadKey, imsName string) datasetSpec {
	return datasetSpec{
		rawTable: rawTable, partCol: "", partitions: singlePartition,
		family: familyRailSingle, apiSeg: apiSeg,
		name:    func(string) string { return imsName },
		loadKey: loadKey,
	}
}

// datasetRegistry is the ordered dataset table. Slice order is the load order:
// filtering to loadKey-bearing entries yields exactly the legacy loaderRegistry
// order, so the bus_operator-before-bus invariant is structural (bus_operator is
// listed first and loadBus reads bus_operators back after it upserts).
func datasetRegistry() []datasetSpec {
	return []datasetSpec{
		busDataset("Operator", "bus_operator", "bus_operator", ""),
		busDataset("Route", "bus_route", "bus", ""),
		busDataset("StopOfRoute", "bus_stopofroute", "", "bus"),
		busDataset("Shape", "bus_shape", "", "bus"),
		busDataset("Schedule", "bus_schedule", "", "bus"),
		busDataset("Station", "bus_station", "", "bus"),
		busDataset("StationGroup", "bus_stationgroup", "", "bus"),
		busDataset("RouteFare", "bus_routefare", "", "bus"),
		// Landed for every city (TDX serves an empty payload for the skip cities),
		// but only loaded for the cities whose daily-timetable feed TDX serves.
		{rawTable: "bus_dailytimetable", partCol: "city", partitions: allCities,
			loadParts: dailyTimetableCities, family: familyBusCity, apiSeg: "DailyTimeTable",
			name: busName("DailyTimeTable"), loadKey: "bus_dailytimetable"},
		// Bus/Stop is intentionally absent from the fetch and reverse maps: it is
		// never fetched and never loaded. The whitelist/DDL entry is kept because
		// the table may already exist on Azure.
		{rawTable: "bus_stop", landOnly: true},
		{rawTable: "bike_station", partCol: "city", partitions: bikeCities,
			family: familyBikeCity, apiSeg: "Station",
			name: func(p string) string { return "bike_" + p }, loadKey: "bike"},
		{rawTable: "metro_station", partCol: "system", partitions: func() []string { return ingestMetroStationSystems },
			family: familyMetroSystem, apiSeg: "Station",
			name: func(p string) string { return "metro_station_" + p }, loadKey: "mrt_station"},
		{rawTable: "metro_schedule", partCol: "system", partitions: func() []string { return ingestMetroFirstLast },
			family: familyMetroSystem, apiSeg: "FirstLastTimetable",
			name: func(p string) string { return "metro_fl_" + p }, loadKey: "mrt_firstlast", staleOK: true},
		{rawTable: "metro_odfare", partCol: "system", partitions: func() []string { return ingestMetroODFare },
			family: familyMetroSystem, apiSeg: "ODFare",
			name: func(p string) string { return "metro_od_" + p }, loadKey: "mrt_odfare"},
		{rawTable: "metro_s2straveltime", partCol: "system", partitions: func() []string { return ingestMetroTravelGraph },
			family: familyMetroSystem, apiSeg: "S2STravelTime",
			name: func(p string) string { return "metro_s2s_" + p }, loadKey: "mrt_trtc_traveltime"},
		{rawTable: "metro_linetransfer", partCol: "system", partitions: func() []string { return ingestMetroTravelGraph },
			family: familyMetroSystem, apiSeg: "LineTransfer",
			name: func(p string) string { return "metro_transfer_" + p }, foldedInto: "mrt_trtc_traveltime"},
		railSingle("TRA/Station", "tra_station", "tra_station", "tra_station"),
		railSingle("THSR/Station", "thsr_station", "thsr_station", "thsr_station"),
		railSingle("TRA/ODFare", "tra_odfare", "tra_fare", "tra_odfare"),
		railSingle("THSR/ODFare", "thsr_odfare", "thsr_fare", "thsr_odfare"),
		{rawTable: "tra_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(60) },
			family: familyRailDate, apiSeg: "TRA/DailyTimetable",
			name: func(p string) string { return "tra_daily_" + p }, loadKey: "tra_timetable"},
		{rawTable: "thsr_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(45) },
			family: familyRailDate, apiSeg: "THSR/DailyTimetable",
			name: func(p string) string { return "thsr_daily_" + p }, loadKey: "thsr_timetable"},
		// TRA/TrainType resolves on the reverse path (its DDL/whitelist entry is
		// kept) but is never fetched: nothing loads raw_tdx.tra_traintype, and
		// train-type data arrives inside the daily-timetable payloads.
		{rawTable: "tra_traintype", family: familyRailSingle, apiSeg: "TRA/TrainType", landOnly: true},
	}
}

// famSeg keys the reverse index: (family, endpoint segment) → dataset. The
// segment is family-scoped so bus "Station" and metro "Station" do not collide.
type famSeg struct {
	family landFamily
	seg    string
}

// rawTargetIndex resolves a parsed landing URL back to its dataset. It includes
// every reverse-mappable dataset (family != familyNone), so landOnly-but-mappable
// tables like tra_traintype still resolve while the unfetched bus_stop
// (familyNone) does not — matching the legacy rawDumpTarget maps exactly.
var rawTargetIndex = buildRawTargetIndex()

func buildRawTargetIndex() map[famSeg]datasetSpec {
	m := make(map[famSeg]datasetSpec)
	for _, d := range datasetRegistry() {
		if d.family == familyNone {
			continue
		}
		m[famSeg{d.family, d.apiSeg}] = d
	}
	return m
}
