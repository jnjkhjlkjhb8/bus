package shared

import "github.com/samber/oops"

// _oops is this package's error builder. Every error raised here carries the
// domain, so Sentry and the log backend can group by the area that failed
// without parsing message text. Variable data goes in .With() attributes rather
// than the message, keeping messages low-cardinality for aggregation.
var _oops = oops.In("shared")
