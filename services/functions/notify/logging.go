package notify

import "github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"

// log routes this package's legacy log calls through obs's slog backend.
var log = obs.SlogCompat{}
