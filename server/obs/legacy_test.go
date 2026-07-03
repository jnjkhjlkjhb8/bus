package obs

import (
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/getsentry/sentry-go"
)

func TestLogfMapsLegacyFields(t *testing.T) {
	logger, tr := newDiscardLogger(t)
	slog.SetDefault(logger)
	Logf("[BUS] action=dailyRoute city=%s event=cleanup_error error=%v", "Taipei", errors.New("boom"))
	if len(tr.events) != 1 {
		t.Fatalf("expected 1 sentry event, got %d", len(tr.events))
	}
	tags := tr.events[0].Tags
	if tr.events[0].Level != sentry.LevelError {
		t.Fatalf("expected error level, got %v", tr.events[0].Level)
	}
	if tags["service"] != "bus" || tags["action"] != "dailyRoute" || tags["city"] != "Taipei" || tags["event"] != "cleanup_error" {
		t.Fatalf("unexpected tags %v", tags)
	}
}

func newDiscardLogger(t *testing.T) (*slog.Logger, *fakeTransport) {
	t.Helper()
	tr := &fakeTransport{}
	err := sentry.Init(sentry.ClientOptions{
		Dsn:       "https://key@example.com/1",
		Transport: tr,
	})
	if err != nil {
		t.Fatal(err)
	}
	return slog.New(NewHandler(slog.NewJSONHandler(io.Discard, nil))), tr
}
