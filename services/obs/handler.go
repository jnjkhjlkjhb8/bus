package obs

import (
	"fmt"
	"slices"
	"strings"

	"github.com/getsentry/sentry-go"
	"go.uber.org/zap/zapcore"
)

type sentryCore struct {
	zapcore.Core
	// fields accumulated through With. The embedded core keeps its own copy for
	// encoding, but does not expose them, and a Sentry event needs every field
	// the logger carries -- not just the ones passed at the call site.
	fields []zapcore.Field
}

// NewCore wraps inner so that entries at Error level or above are also
// forwarded to Sentry as a captured message, with fields copied onto the scope
// as tags (the "err" field becomes an error context instead). Forwarding is
// skipped when Sentry has no active client, so with no DSN this behaves as a
// pass-through to inner, and for entries whose "err" reads as transient (see
// transientErr). Init installs this around a JSON core.
func NewCore(inner zapcore.Core) zapcore.Core {
	return &sentryCore{Core: inner}
}

func (c *sentryCore) With(fields []zapcore.Field) zapcore.Core {
	return &sentryCore{
		Core:   c.Core.With(fields),
		fields: append(slices.Clip(c.fields), fields...),
	}
}

// Check must be overridden rather than inherited: the embedded core would add
// itself to the checked entry, and this core's Write -- the Sentry hook --
// would never run.
func (c *sentryCore) Check(ent zapcore.Entry, ce *zapcore.CheckedEntry) *zapcore.CheckedEntry {
	if c.Enabled(ent.Level) {
		return ce.AddCore(ent, c)
	}
	return ce
}

func (c *sentryCore) Write(ent zapcore.Entry, fields []zapcore.Field) error {
	if ent.Level >= zapcore.ErrorLevel && sentry.CurrentHub().Client() != nil {
		c.capture(ent, fields)
	}
	return c.Core.Write(ent, fields)
}

func (c *sentryCore) capture(ent zapcore.Entry, fields []zapcore.Field) {
	enc := zapcore.NewMapObjectEncoder()
	for _, f := range c.fields {
		f.AddTo(enc)
	}
	for _, f := range fields {
		f.AddTo(enc)
	}

	errVal, hasErr := enc.Fields["err"]
	errText := ""
	if hasErr {
		errText = valueText(errVal)
		if transientErr(errText) {
			return
		}
	}

	hub := sentry.CurrentHub().Clone()
	hub.Scope().SetLevel(sentry.LevelError)
	hub.Scope().SetTag("source", "zap")
	for k, v := range enc.Fields {
		if k == "err" {
			continue
		}
		hub.Scope().SetTag(k, valueText(v))
	}
	if hasErr {
		hub.Scope().SetContext("error", sentry.Context{"detail": errText})
	}
	hub.CaptureMessage(ent.Message)
}

func valueText(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case error:
		return t.Error()
	default:
		return fmt.Sprint(v)
	}
}

// transientErr reports whether an error string describes a self-healing
// condition — a timeout or a backend still coming up — rather than a defect.
// These stay on stderr at their logged level but raise no Sentry issue, so a
// single nightly-batch hiccup does not page anyone. A sustained outage still
// surfaces through the startup connect panic; add a consecutive-failure
// counter here if that proves too quiet.
func transientErr(val string) bool {
	lower := strings.ToLower(val)
	for _, s := range []string{"context deadline exceeded", "timeout", "connection refused", "connection reset", "loading redis"} {
		if strings.Contains(lower, s) {
			return true
		}
	}
	return false
}
