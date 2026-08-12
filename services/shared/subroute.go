package shared

// CanonicalSubroute collapses an InterCity (THB) subroute's two travel
// directions onto one canonical UID plus a derived direction. InterCity TDX
// data encodes direction inside the UID itself: the paired variants arrive as
// distinct UIDs (THB902301/THB902302, THB9023A1/THB9023A2) rather than one UID
// with a Direction field. City-bus data instead keys both directions under one
// UID and carries direction separately, so non-InterCity cities pass through
// unchanged.
//
// The suffix is read the way TDX documents SubRouteID: a route code, then one
// character for main/branch ('0' for the main route, a letter for a branch),
// then one character for the travel direction ('1' outbound, '2' inbound). So:
//
//   - "…01"/"…02" is the main route's pair: both characters are stripped, since
//     the canonical UID of a main route is its route code.
//   - a branch letter followed by a direction character ("…A1", "…A2") keeps the
//     letter — it is part of the branch's identity — and drops only the
//     direction.
//   - anything else does not carry the suffix and is returned whole. A route UID
//     (THB0968) reaching here is the case that matters: stripping its last
//     character invented a UID nothing in the feed uses. Leaving it whole also
//     makes this idempotent, so a second canonicalization of an already
//     canonical UID is a no-op rather than a second strip.
//
// Direction always comes from the UID, never from the caller's Direction field.
// Measured against TDX's InterCity Route dataset (2026-08-09, 1,780 subroutes):
// every UID matches one of the two shapes above, and '1'/'2' agree with the
// published Direction 0/1 without exception.
//
// The suffix shapes are TDX-format-dependent and must not be relied on beyond
// what TDX currently emits (ADR-0006). Callers on the ingestion boundary produce
// canonical UIDs; nothing downstream re-derives them.
//
// A UID shorter than the slice it would take is returned unchanged so a
// malformed short UID cannot panic.
func CanonicalSubroute(city, subRouteUID string, direction uint8) (string, uint8) {
	if city != "InterCity" || len(subRouteUID) < 2 {
		return subRouteUID, direction
	}
	suffixDir, ok := subrouteSuffixDirection(subRouteUID)
	if !ok {
		return subRouteUID, direction
	}
	if subRouteUID[len(subRouteUID)-2] == '0' {
		return subRouteUID[:len(subRouteUID)-2], suffixDir
	}
	return subRouteUID[:len(subRouteUID)-1], suffixDir
}

// subrouteSuffixDirection reads the travel direction off a UID's last character,
// reporting false when the UID does not end in a main/branch marker followed by
// a direction and so carries no suffix to strip.
func subrouteSuffixDirection(uid string) (uint8, bool) {
	marker := uid[len(uid)-2]
	if marker != '0' && (marker < 'A' || marker > 'Z') {
		return 0, false
	}
	switch uid[len(uid)-1] {
	case '1':
		return 0, true
	case '2':
		return 1, true
	}
	return 0, false
}
