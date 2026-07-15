package obs

import (
	"context"
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

// Warnf/Warn/Error pin their slog level explicitly instead of inferring it
// from message prose, unlike Logf/Infof. A call site that already knows a
// condition is a handled skip (Warnf) or a real failure (Error) must not have
// that severity second-guessed by keyword matching over the formatted text.
func TestSlogCompatWarnfLogsAtWarnLevelRegardlessOfMessageText(t *testing.T) {
	captured := &captureHandler{}
	slog.SetDefault(slog.New(captured))
	// The message text itself reads like a hard failure ("event=failed"), but
	// the call site chose Warnf, so the emitted level must be Warn, not the
	// Error a prose scan of "failed" would infer.
	SlogCompat{}.Warnf("[TDX] action=fetch event=failed reason=%s", "rate_limited")
	if len(captured.records) != 1 {
		t.Fatalf("records = %d, want 1", len(captured.records))
	}
	if captured.records[0].Level != slog.LevelWarn {
		t.Fatalf("level = %v, want %v", captured.records[0].Level, slog.LevelWarn)
	}
}

func TestSlogCompatWarnLogsAtWarnLevel(t *testing.T) {
	logger, transport := newDiscardLogger(t)
	slog.SetDefault(logger)
	SlogCompat{}.Warn("connection lost, auto-reconnecting")
	if len(transport.events) != 0 {
		t.Fatalf("Warn-level logs must not raise a Sentry error event, got %d", len(transport.events))
	}
}

func TestSlogCompatErrorLogsAtErrorLevelWithoutExiting(t *testing.T) {
	logger, transport := newDiscardLogger(t)
	slog.SetDefault(logger)
	SlogCompat{}.Error("router stopped", "reason", "serve failed")
	if len(transport.events) != 1 {
		t.Fatalf("error events = %d, want 1", len(transport.events))
	}
	if transport.events[0].Level != sentry.LevelError {
		t.Fatalf("error level = %v, want %v", transport.events[0].Level, sentry.LevelError)
	}
}

// Errorf must not skip Sentry reporting for a call site that includes the
// legacy "[TAG] key=value" shape: parsing into attrs and pinning the level
// explicitly are independent — explicit level selection must not silently
// drop the structured tags call sites already rely on for triage.
func TestSlogCompatErrorfParsesStructuredAttrsAtExplicitLevel(t *testing.T) {
	logger, transport := newDiscardLogger(t)
	slog.SetDefault(logger)
	SlogCompat{}.Errorf("[MQTT] action=subscribe topic=%s err=%v", "bus/eta", errors.New("dial refused"))
	if len(transport.events) != 1 {
		t.Fatalf("expected 1 sentry event, got %d", len(transport.events))
	}
	if transport.events[0].Tags["service"] != "mqtt" || transport.events[0].Tags["topic"] != "bus/eta" {
		t.Fatalf("unexpected tags %v", transport.events[0].Tags)
	}
}

type captureHandler struct {
	records []slog.Record
}

func (h *captureHandler) Enabled(context.Context, slog.Level) bool { return true }
func (h *captureHandler) Handle(_ context.Context, r slog.Record) error {
	h.records = append(h.records, r)
	return nil
}
func (h *captureHandler) WithAttrs(attrs []slog.Attr) slog.Handler { return h }
func (h *captureHandler) WithGroup(name string) slog.Handler       { return h }

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
