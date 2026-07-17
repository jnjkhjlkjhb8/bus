// Package obs provides Sentry-backed error tracking plus small error and
// retry helpers shared by the router and functions binaries. When SENTRY_DSN
// is empty, Sentry is not initialized and the capture paths become no-ops
// while structured slog output continues unchanged.
package obs

import (
	"context"
	"log/slog"
	"net/url"
	"os"
	"strconv"
	"time"

	"github.com/getsentry/sentry-go"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Init installs the slog default logger (JSON, tagged with service) and, when
// SENTRY_DSN is set, initializes Sentry. The returned function flushes buffered
// events and must be deferred; with no DSN, or if init fails, it is a no-op.
// SENTRY_TRACES_SAMPLE_RATE (default 0.1) tunes tracing; an unparseable value
// is ignored.
func Init(service string) func() {
	logger := slog.New(NewHandler(slog.NewJSONHandler(os.Stderr, nil))).With("service", service)
	slog.SetDefault(logger)
	dsn := os.Getenv("SENTRY_DSN")
	if dsn == "" {
		slog.Info("sentry disabled", "reason", "no_dsn")
		return func() {}
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
		slog.Error("sentry init failed", "err", err)
		return func() {}
	}
	sentry.ConfigureScope(func(scope *sentry.Scope) {
		scope.SetTag("service", service)
	})
	slog.Info("sentry enabled", "traces", tracesRate)
	return func() { sentry.Flush(2 * time.Second) }
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
