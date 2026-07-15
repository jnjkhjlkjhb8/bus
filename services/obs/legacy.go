package obs

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"strings"
)

// SlogCompat adapts the standard library log.Logger-style interface
// (Infof/Infoln/Errorf/Fatal/Fatalf) onto slog, so third-party code expecting that
// method set routes through the same structured pipeline. Pass it where a
// logger with these methods is required rather than replacing call sites.
type SlogCompat struct{}

// Infof routes a formatted line through Logf, which parses it into structured
// attributes. It is Info-level only by name; the effective level is inferred
// from the parsed content.
func (SlogCompat) Infof(format string, args ...any) {
	Logf(format, args...)
}

// Infoln routes a space-joined line through Logln. As with Infof the effective
// level is inferred from the parsed content, not fixed at Info.
func (SlogCompat) Infoln(args ...any) {
	Logln(args...)
}

// Errorf logs a formatted message explicitly at Error level without exiting.
func (SlogCompat) Errorf(format string, args ...any) {
	slog.Error(fmt.Sprintf(format, args...))
}

// Fatal logs the args at Error level and exits the process with status 1,
// matching log.Fatal semantics. It does not go through the legacy parser.
func (SlogCompat) Fatal(args ...any) {
	slog.Error(strings.TrimSpace(fmt.Sprintln(args...)))
	os.Exit(1)
}

// Fatalf logs the formatted message at Error level and exits with status 1,
// matching log.Fatalf semantics. It does not go through the legacy parser.
func (SlogCompat) Fatalf(format string, args ...any) {
	slog.Error(fmt.Sprintf(format, args...))
	os.Exit(1)
}

// Logf formats a legacy log line and emits it through the parser that turns
// "key=value event=..." text into structured slog attributes and an inferred
// level. Retained for call sites not yet migrated to slog directly.
func Logf(format string, args ...any) {
	emitLegacyLog(fmt.Sprintf(format, args...))
}

// Logln is the space-joined counterpart to Logf, emitting the joined args
// through the same legacy parser.
func Logln(args ...any) {
	emitLegacyLog(strings.TrimSpace(fmt.Sprintln(args...)))
}

func emitLegacyLog(line string) {
	msg, attrs := legacyAttrs(line)
	slog.Log(context.Background(), legacyLevel(attrs), msg, attrs...)
}

// transientErr reports whether an error string describes a self-healing
// condition — a timeout or a backend still coming up — rather than a defect.
// These log at Warn so they stay in stdout but do not raise a Sentry error
// issue for a single nightly-batch hiccup. A sustained outage still surfaces
// through the startup connect panic and Sentry event counts; add a
// consecutive-failure counter here if that proves too quiet.
func transientErr(val string) bool {
	lower := strings.ToLower(val)
	for _, s := range []string{"context deadline exceeded", "timeout", "connection refused", "connection reset", "loading redis"} {
		if strings.Contains(lower, s) {
			return true
		}
	}
	return false
}

func legacyLevel(attrs []any) slog.Level {
	errVal := ""
	eventVal := ""
	for i := 0; i+1 < len(attrs); i += 2 {
		key, _ := attrs[i].(string)
		val, _ := attrs[i+1].(string)
		switch key {
		case "err":
			if val != "" && val != "<nil>" && !strings.HasPrefix(val, "%!") {
				errVal = val
			}
		case "event":
			eventVal = strings.ToLower(val)
		}
	}

	// A skip/fallback event is a handled outcome; keep it at Warn even when an
	// error value is attached (e.g. an embed request that was skipped).
	if strings.Contains(eventVal, "skip") || strings.Contains(eventVal, "invalid") ||
		strings.Contains(eventVal, "fallback") || strings.Contains(eventVal, "not_set") {
		return slog.LevelWarn
	}
	if errVal != "" && transientErr(errVal) {
		return slog.LevelWarn
	}
	if errVal != "" || strings.Contains(eventVal, "fail") || strings.Contains(eventVal, "error") {
		return slog.LevelError
	}
	return slog.LevelInfo
}

func legacyAttrs(line string) (string, []any) {
	attrs := make([]any, 0, 10)
	rest := line
	if strings.HasPrefix(line, "[") {
		if end := strings.Index(line, "]"); end > 1 {
			attrs = append(attrs, "service", strings.ToLower(line[1:end]))
			rest = strings.TrimSpace(line[end+1:])
		}
	}

	head := rest
	errVal := ""
	hasErr := false
	for _, marker := range []string{"error=", "err="} {
		if i := strings.Index(rest, marker); i >= 0 {
			head = strings.TrimSpace(rest[:i])
			errVal = strings.TrimSpace(rest[i+len(marker):])
			hasErr = true
			break
		}
	}

	msg := head
	for _, field := range strings.Fields(head) {
		key, value, ok := strings.Cut(field, "=")
		if !ok || key == "" {
			continue
		}
		key = strings.Trim(key, " :,")
		value = strings.Trim(value, " :,")
		attrs = append(attrs, key, value)
		if key == "event" {
			msg = strings.ReplaceAll(value, "_", " ")
		}
	}
	if hasErr {
		attrs = append(attrs, "err", errVal)
	}
	if msg == "" {
		msg = "log"
	}
	return msg, attrs
}
