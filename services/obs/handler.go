package obs

import (
	"context"
	"log/slog"

	"github.com/getsentry/sentry-go"
)

type sentryHandler struct {
	inner slog.Handler
}

// NewHandler wraps inner so that records at Error level or above are also
// forwarded to Sentry as a captured message, with attributes copied onto the
// scope as tags (the "err" attribute becomes an error context instead).
// Forwarding is skipped when Sentry has no active client, so with no DSN this
// behaves as a pass-through to inner. Init installs this around a JSON handler.
func NewHandler(inner slog.Handler) slog.Handler {
	return &sentryHandler{inner: inner}
}

func (h *sentryHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.inner.Enabled(ctx, level)
}

func (h *sentryHandler) Handle(ctx context.Context, r slog.Record) error {
	if r.Level >= slog.LevelError && sentry.CurrentHub().Client() != nil {
		hub := sentry.CurrentHub().Clone()
		hub.Scope().SetLevel(sentry.LevelError)
		hub.Scope().SetTag("source", "slog")
		r.Attrs(func(a slog.Attr) bool {
			if a.Key == "err" {
				hub.Scope().SetContext("error", sentry.Context{"detail": a.Value.String()})
			} else {
				hub.Scope().SetTag(a.Key, a.Value.String())
			}
			return true
		})
		hub.CaptureMessage(r.Message)
	}
	return h.inner.Handle(ctx, r)
}

func (h *sentryHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &sentryHandler{inner: h.inner.WithAttrs(attrs)}
}

func (h *sentryHandler) WithGroup(name string) slog.Handler {
	return &sentryHandler{inner: h.inner.WithGroup(name)}
}
