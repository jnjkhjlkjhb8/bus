package obs

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
)

type fakeTransport struct{ events []*sentry.Event }

func (t *fakeTransport) Configure(sentry.ClientOptions) {}
func (t *fakeTransport) SendEvent(e *sentry.Event)      { t.events = append(t.events, e) }
func (t *fakeTransport) Flush(time.Duration) bool       { return true }
func (t *fakeTransport) FlushWithContext(context.Context) bool {
	return true
}
func (t *fakeTransport) Close() {}

func newTestLogger(t *testing.T) (*slog.Logger, *fakeTransport) {
	t.Helper()
	tr := &fakeTransport{}
	err := sentry.Init(sentry.ClientOptions{
		Dsn:       "https://key@example.com/1",
		Transport: tr,
	})
	if err != nil {
		t.Fatal(err)
	}
	return slog.New(NewHandler(slog.NewJSONHandler(os.Stderr, nil))), tr
}

func TestHandlerErrorGoesToSentry(t *testing.T) {
	logger, tr := newTestLogger(t)
	logger.Error("ingest failed", "action", "busStatic", "err", errors.New("boom"))
	if len(tr.events) != 1 {
		t.Fatalf("expected 1 sentry event, got %d", len(tr.events))
	}
	if tr.events[0].Message != "ingest failed" {
		t.Fatalf("unexpected message %q", tr.events[0].Message)
	}
	if tr.events[0].Level != sentry.LevelError {
		t.Fatalf("expected error level, got %v", tr.events[0].Level)
	}
	if tr.events[0].Tags["source"] != "slog" {
		t.Fatalf("expected slog source tag, got %v", tr.events[0].Tags)
	}
	if tr.events[0].Tags["action"] != "busStatic" {
		t.Fatalf("expected action tag, got %v", tr.events[0].Tags)
	}
	if _, ok := tr.events[0].Tags["err"]; ok {
		t.Fatal("err should not be a tag")
	}
	if tr.events[0].Contexts["error"] == nil {
		t.Fatalf("expected error context, got %v", tr.events[0].Contexts)
	}
}

func TestHandlerWarnInfoNotReported(t *testing.T) {
	logger, tr := newTestLogger(t)
	logger.Warn("parse skipped", "err", errors.New("bad float"))
	logger.Info("done")
	if len(tr.events) != 0 {
		t.Fatalf("expected 0 sentry events, got %d", len(tr.events))
	}
}
