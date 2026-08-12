// Package obs provides Sentry-backed error tracking plus small error and
// retry helpers shared by the router and functions binaries. When SENTRY_DSN
// is empty, Sentry is not initialized and the capture paths become no-ops
// while structured zap output continues unchanged.
package obs

import (
	"context"
	"net/url"
	"os"
	"strconv"
	"time"

	"github.com/getsentry/sentry-go"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Init installs the zap global logger (JSON, tagged with service) that every
// call site reaches through zap.L/zap.S, and, when SENTRY_DSN is set,
// initializes Sentry. The returned function flushes buffered events and must be
// deferred. SENTRY_TRACES_SAMPLE_RATE (default 0.1) tunes tracing; an
// unparseable value is ignored.
func Init(service string) func() {
	logger := zap.New(NewCore(newZapCore())).With(zap.String("service", service))
	zap.ReplaceGlobals(logger)
	// zap buffers nothing when writing straight to stderr, but Sync is the
	// documented contract and keeps this correct if the sink ever changes.
	sync := func() { _ = logger.Sync() }
	dsn := os.Getenv("SENTRY_DSN")
	if dsn == "" {
		zap.S().Infow("sentry disabled", "reason", "no_dsn")
		return sync
	}
	tracesRate := 0.1
	if v := os.Getenv("SENTRY_TRACES_SAMPLE_RATE"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			tracesRate = f
		}
	}
	err := sentry.Init(sentry.ClientOptions{
		Dsn:                   dsn,
		Environment:           os.Getenv("SENTRY_ENVIRONMENT"),
		ServerName:            service,
		EnableTracing:         tracesRate > 0,
		TracesSampleRate:      tracesRate,
		BeforeSend:            scrubSentryEventQuery,
		BeforeSendTransaction: scrubSentryEventQuery,
	})
	if err != nil {
		zap.S().Errorw("sentry init failed", "err", err)
		return sync
	}
	sentry.ConfigureScope(func(scope *sentry.Scope) {
		scope.SetTag("service", service)
	})
	zap.S().Infow("sentry enabled", "traces", tracesRate)
	return func() {
		sentry.Flush(2 * time.Second)
		sync()
	}
}

// newZapCore builds the JSON core every process logs through. The field names
// and encodings reproduce the slog JSONHandler output this replaced
// (time/level/msg, RFC3339 nanoseconds, uppercase levels) so existing log
// queries keep matching. Caller, logger name, and stacktrace keys are omitted:
// nothing names a logger, and the fields already say where a line came from.
// Info is the floor, as it was under slog.
func newZapCore() zapcore.Core {
	encoder := zapcore.EncoderConfig{
		TimeKey:        "time",
		LevelKey:       "level",
		MessageKey:     "msg",
		NameKey:        zapcore.OmitKey,
		CallerKey:      zapcore.OmitKey,
		FunctionKey:    zapcore.OmitKey,
		StacktraceKey:  zapcore.OmitKey,
		LineEnding:     zapcore.DefaultLineEnding,
		EncodeLevel:    zapcore.CapitalLevelEncoder,
		EncodeTime:     zapcore.RFC3339NanoTimeEncoder,
		EncodeDuration: zapcore.StringDurationEncoder,
	}
	return zapcore.NewCore(zapcore.NewJSONEncoder(encoder), zapcore.Lock(os.Stderr), zapcore.InfoLevel)
}

// scrubSentryEventQuery removes credentials and other query parameters from
// both error and transaction events while retaining the request path and method.
func scrubSentryEventQuery(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
	if event == nil || event.Request == nil {
		return event
	}
	event.Request.QueryString = ""
	if parsed, err := url.Parse(event.Request.URL); err == nil {
		parsed.RawQuery = ""
		parsed.ForceQuery = false
		event.Request.URL = parsed.String()
	}
	return event
}

// Recover is a deferred panic handler that reports the panic to Sentry tagged
// with the given job name, then re-panics so the caller's normal crash
// behavior is preserved. With no DSN the report is dropped but the re-panic
// still occurs.
func Recover(name string) {
	if r := recover(); r != nil {
		hub := sentry.CurrentHub().Clone()
		hub.Scope().SetTag("job", name)
		hub.RecoverWithContext(context.Background(), r)
		hub.Flush(2 * time.Second)
		panic(r)
	}
}

// Capture reports err to Sentry tagged with the given job name. A nil err is
// ignored. Unlike Recover it does not re-raise anything, so callers keep
// running after the report. With no DSN the clone has no client and the
// report is silently dropped.
func Capture(name string, err error) {
	if err == nil {
		return
	}
	hub := sentry.CurrentHub().Clone()
	hub.Scope().SetTag("job", name)
	applyOopsScope(hub.Scope(), err)
	hub.CaptureException(err)
}

// UnaryInterceptor returns a gRPC unary interceptor that puts a per-request
// Sentry hub (tagged with the method) on the context, recovers panics from
// downstream handlers, and records the call in the router_grpc_requests_total
// / router_grpc_errors_total counters (see metrics.go) -- the single choke
// point every unary RPC passes through, so this covers the whole API surface
// without touching individual handlers. A recovered panic is reported to
// Sentry and converted into a codes.Internal status so the panic does not
// escape the gRPC server; the generic "internal error" message avoids
// leaking internals to clients.
func UnaryInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (_ any, err error) {
		hub := sentry.CurrentHub().Clone()
		hub.Scope().SetTag("grpc.method", info.FullMethod)
		ctx = sentry.SetHubOnContext(ctx, hub)
		defer func() {
			if r := recover(); r != nil {
				hub.RecoverWithContext(ctx, r)
				err = status.Errorf(codes.Internal, "internal error")
			}
			RecordGRPCRequest(info.FullMethod, err)
		}()
		return handler(ctx, req)
	}
}

// StreamInterceptor is the streaming counterpart to UnaryInterceptor: it tags
// a cloned hub with the method, recovers panics from the stream handler
// (reporting them and returning a codes.Internal status), and records the
// call in the same router_grpc_requests_total / router_grpc_errors_total
// counters. The hub is not placed on the stream context here because
// ServerStream carries its own context.
func StreamInterceptor() grpc.StreamServerInterceptor {
	return func(srv any, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) (err error) {
		hub := sentry.CurrentHub().Clone()
		hub.Scope().SetTag("grpc.method", info.FullMethod)
		defer func() {
			if r := recover(); r != nil {
				hub.RecoverWithContext(ss.Context(), r)
				err = status.Errorf(codes.Internal, "internal error")
			}
			RecordGRPCRequest(info.FullMethod, err)
		}()
		return handler(srv, ss)
	}
}
