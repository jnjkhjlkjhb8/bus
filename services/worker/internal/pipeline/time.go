package pipeline

import "time"

// Taipei is the one timezone the whole schedule domain is expressed in.
var Taipei = mustLoadTaipei()

// mustLoadTaipei resolves the one timezone the whole schedule domain is
// expressed in. It replaces an init(): package-level var initialization is
// ordered by dependency rather than by filename, so anything else in the
// package that reads taipei at init time is guaranteed a loaded location.
// A missing tzdata is a broken build, not a runtime condition to handle.
func mustLoadTaipei() *time.Location {
	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		panic("cannot load Asia/Taipei: " + err.Error())
	}
	return loc
}
