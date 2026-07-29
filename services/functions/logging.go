package main

import "github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"

// log is the package-wide structured logger. SlogCompat exposes Infof/Infoln
// shims so this package's legacy log calls route through obs's slog backend.
var log = obs.SlogCompat{}
