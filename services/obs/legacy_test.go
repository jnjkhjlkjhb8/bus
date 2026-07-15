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

func TestSlogCompatErrorfLogsAtErrorLevelWithoutExiting(t *testing.T) {
	logger, transport := newDiscardLogger(t)
	slog.SetDefault(logger)
	SlogCompat{}.Errorf("router stopped: %s", "serve failed")
	if len(transport.events) != 1 {
		t.Fatalf("error events = %d, want 1", len(transport.events))
	}
	if transport.events[0].Level != sentry.LevelError {
		t.Fatalf("error level = %v, want %v", transport.events[0].Level, sentry.LevelError)
	}
}

func TestLegacyLevel(t *testing.T) {
	cases := []struct {
		name string
		line string
		want slog.Level
	}{
		{"error event with real err", "[BUS] action=x event=cleanup_error error=boom", slog.LevelError},
		{"handled skip keeps warn despite err", "[vector] action=vector event=skip reason=api_error,error=dial tcp: i/o timeout", slog.LevelWarn},
		{"transient timeout demoted", "[LOAD] action=bus api=RouteFare event=read_error error=timeout: context deadline exceeded", slog.LevelWarn},
		{"redis loading demoted", "[REDIS] action=connect event=failed error=LOADING Redis is loading the dataset in memory", slog.LevelWarn},
		{"plain info", "[BUS] action=x event=done count=3", slog.LevelInfo},
	}
	for _, c := range cases {
		_, attrs := legacyAttrs(c.line)
		if got := legacyLevel(attrs); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
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
