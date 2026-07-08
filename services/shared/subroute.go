package shared

// CanonicalSubroute collapses an InterCity (THB) subroute's two travel
// directions onto one canonical UID plus a derived direction. InterCity TDX
// data encodes direction inside the UID itself: the paired variants arrive as
// distinct UIDs (THB902301/THB902302, THB9023A1/THB9023A0) rather than one UID
// with a Direction field. City-bus data instead keys both directions under one
// UID and carries direction separately, so non-InterCity cities pass through
// unchanged.
//
// The heuristic: a trailing "01"/"02" pair maps to direction 0/1 and is
// stripped; any other InterCity suffix strips a single trailing character and
// keeps the supplied direction. The suffix shapes are TDX-format-dependent and
// must not be relied on beyond what TDX currently emits (ADR-0006). Callers on
// the ingestion boundary produce canonical UIDs; nothing downstream re-derives
// them.
//
// A UID shorter than the slice it would take is returned unchanged so a
// malformed short UID cannot panic.
func CanonicalSubroute(city, subRouteUID string, direction uint8) (string, uint8) {
	if city != "InterCity" {
		return subRouteUID, direction
	}
	if len(subRouteUID) < 2 {
		return subRouteUID, direction
	}
	switch subRouteUID[len(subRouteUID)-2:] {
	case "01":
		return subRouteUID[:len(subRouteUID)-2], 0
	case "02":
		return subRouteUID[:len(subRouteUID)-2], 1
	}
	return subRouteUID[:len(subRouteUID)-1], direction
}
