package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	// _feedbackBodyLimit is counted in runes, not bytes: the reports are written
	// in Chinese, where a byte limit would cut the usable length to a third.
	_feedbackBodyLimit = 2000
	// _feedbackFieldLimit bounds each diagnostics value. They are short, fixed
	// strings the client assembles (version, platform, locale, route pattern),
	// so anything longer is a client defect or an injection attempt.
	_feedbackFieldLimit = 128
)

type feedbackPersistence interface {
	OpenThread(context.Context, feedbackThreadRecord, string) (time.Time, error)
}

// installAuthorizer is the slice of the device store the feedback path needs:
// it authenticates the caller against the per-installation secret without
// giving this service any way to read or write device rows.
type installAuthorizer interface {
	AuthorizeInstall(context.Context, string, []byte) (bool, error)
}

// FeedbackServer accepts rider-written problem reports. Riders are anonymous —
// there is no account system — so the caller is authenticated exactly like
// every other device-scoped RPC: against the install secret it registered with.
// That is what makes the per-installation quota meaningful, since an
// unauthenticated caller could otherwise mint a fresh install_id per request.
type FeedbackServer struct {
	pb.UnimplementedFeedback_ServiceServer
	store    feedbackPersistence
	devices  installAuthorizer
	notifier feedbackNotifier
}

// PostFeedback opens a thread with the rider's message on it and returns the
// thread id, whose first characters the app shows as a case number.
//
// Ops notification is deliberately not part of the RPC's success condition: a
// report that is durable in Postgres has been received, whether or not a chat
// webhook was reachable at that moment.
func (s *FeedbackServer) PostFeedback(ctx context.Context, request *pb.PostFeedbackRequest) (*pb.ReportReceipt, error) {
	if !ValidText(request.GetInstallId(), 128) {
		return nil, status.Error(codes.InvalidArgument, "install_id is required")
	}
	if !validFeedbackCategory(request.GetCategory()) {
		return nil, status.Error(codes.InvalidArgument, "category must be route_data, eta, crash or suggestion")
	}
	// Trimmed rather than rejected for surrounding whitespace: a trailing
	// newline from a multiline field is the rider's keyboard, not a bad client.
	body := strings.TrimSpace(request.GetBody())
	if body == "" {
		return nil, status.Error(codes.InvalidArgument, "body is required")
	}
	if utf8.RuneCountInString(body) > _feedbackBodyLimit {
		return nil, status.Errorf(codes.InvalidArgument, "body is limited to %d characters", _feedbackBodyLimit)
	}
	diagnostics, err := feedbackDiagnostics(request.GetDiagnostics())
	if err != nil {
		return nil, err
	}
	if err := authorizeInstallation(ctx, s.devices, request.InstallId); err != nil {
		return nil, err
	}
	threadID, err := NewUUIDv4()
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to open report")
	}
	messageID, err := NewUUIDv4()
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to open report")
	}
	record := feedbackThreadRecord{
		ThreadID:    threadID,
		InstallID:   request.InstallId,
		Category:    request.Category,
		Body:        body,
		Diagnostics: diagnostics,
	}
	createdAt, err := s.store.OpenThread(ctx, record, messageID)
	if errors.Is(err, errFeedbackQuota) {
		return nil, status.Errorf(codes.ResourceExhausted, "at most %d reports per day", _feedbackQuota)
	}
	if err != nil {
		zap.S().Errorw("store failed",
			"component", "feedback",
			"action", "post",
			"event", "store_failed",
			"install", request.InstallId,
			"err", err,
		)
		return nil, status.Error(codes.Internal, "failed to save report")
	}
	s.notifier.Notify(feedbackNotice{
		ThreadID:    threadID,
		Category:    request.Category,
		Body:        body,
		Diagnostics: diagnostics,
	})
	return &pb.ReportReceipt{ThreadId: threadID, CreatedAtUnix: createdAt.Unix()}, nil
}

func validFeedbackCategory(category string) bool {
	switch category {
	case "route_data", "eta", "crash", "suggestion":
		return true
	default:
		return false
	}
}

// feedbackDiagnostics keeps the values the client actually filled in. Empty
// fields are dropped rather than stored as "", so an older client that predates
// a field is distinguishable from a device that could not determine it.
func feedbackDiagnostics(diagnostics *pb.ReportDiagnostics) (map[string]string, error) {
	fields := map[string]string{
		"app_version": diagnostics.GetAppVersion(),
		"platform":    diagnostics.GetPlatform(),
		"os_version":  diagnostics.GetOsVersion(),
		"screen":      diagnostics.GetScreen(),
		"locale":      diagnostics.GetLocale(),
	}
	kept := make(map[string]string, len(fields))
	for name, value := range fields {
		if value == "" {
			continue
		}
		if !ValidText(value, _feedbackFieldLimit) {
			return nil, status.Errorf(codes.InvalidArgument, "diagnostics.%s is malformed", name)
		}
		kept[name] = value
	}
	return kept, nil
}

// feedbackNotice is what ops are told about a new report: everything except the
// install_id, which stays in Postgres. A chat channel is a less controlled
// place than the database, and the identifier is not needed to read a report.
type feedbackNotice struct {
	ThreadID    string
	Category    string
	Body        string
	Diagnostics map[string]string
}

type feedbackNotifier interface{ Notify(feedbackNotice) }

// silentNotifier is what an unset FEEDBACK_WEBHOOK_URL resolves to, mirroring
// how empty TDX credentials disable ingestion: the feature degrades to
// database-only rather than failing or half-configuring itself.
type silentNotifier struct{}

func (silentNotifier) Notify(feedbackNotice) {}

// webhookNotifier posts each report to a Discord-shaped incoming webhook.
type webhookNotifier struct {
	url    string
	client *http.Client
}

func NewFeedbackNotifier() feedbackNotifier {
	url := os.Getenv("FEEDBACK_WEBHOOK_URL")
	if url == "" {
		zap.S().Infow("webhook disabled",
			"component", "feedback",
			"action", "configure",
			"event", "webhook_disabled",
			"reason", "empty_url",
		)
		return silentNotifier{}
	}
	return &webhookNotifier{url: url, client: &http.Client{Timeout: 10 * time.Second}}
}

// Notify returns immediately and posts on its own goroutine with its own
// context. The context that produced the notice is cancelled the moment the
// RPC responds, and the rider must not wait on a chat service to be told their
// report was accepted. A failed post is logged and dropped rather than
// retried: the report is already durable, and a queue for chat notifications
// would be more machinery than the failure is worth.
func (n *webhookNotifier) Notify(notice feedbackNotice) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := n.post(ctx, notice); err != nil {
			zap.S().Warnw("post failed",
				"component", "feedback",
				"action", "notify",
				"event", "post_failed",
				"thread", notice.ThreadID,
				"err", err,
			)
		}
	}()
}

func (n *webhookNotifier) post(ctx context.Context, notice feedbackNotice) error {
	payload, err := json.Marshal(map[string]any{
		"content": feedbackWebhookContent(notice),
		// Rider-authored text reaches a channel verbatim, so mention parsing is
		// switched off wholesale: no @everyone, no role pings, from anyone.
		"allowed_mentions": map[string]any{"parse": []string{}},
	})
	if err != nil {
		return _oops.Wrapf(err, "marshal payload")
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, n.url, bytes.NewReader(payload))
	if err != nil {
		return _oops.Wrapf(err, "build request")
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := n.client.Do(request)
	if err != nil {
		return _oops.Wrapf(err, "send")
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode >= http.StatusMultipleChoices {
		return _oops.With("status", response.Status).Errorf("webhook responded")
	}
	return nil
}

const (
	// _discordContentLimit is Discord's hard cap on a message's content field.
	_discordContentLimit = 2000
	// _feedbackNoticeBodyLimit leaves room for the header and diagnostics line
	// once a maximum-length report is quoted into the message.
	_feedbackNoticeBodyLimit = 1500
)

// feedbackWebhookContent renders one report as a chat message. Every body line
// is quoted so a report containing its own newlines still reads as one block,
// and the whole thing is capped twice — once on the body, once on the result —
// so a long report cannot push the diagnostics line past Discord's limit and
// have the whole POST rejected.
func feedbackWebhookContent(notice feedbackNotice) string {
	var content strings.Builder
	fmt.Fprintf(&content, "**新回報** `%s` · `%s`\n", notice.Category, shortThreadReference(notice.ThreadID))
	for _, line := range strings.Split(truncateRunes(notice.Body, _feedbackNoticeBodyLimit), "\n") {
		content.WriteString("> ")
		content.WriteString(line)
		content.WriteString("\n")
	}
	if summary := feedbackDiagnosticsSummary(notice.Diagnostics); summary != "" {
		content.WriteString(summary)
	}
	return truncateRunes(content.String(), _discordContentLimit)
}

// feedbackDiagnosticsSummary renders the diagnostics in a fixed order, so two
// reports line up when read one after another. Go map iteration would not.
func feedbackDiagnosticsSummary(diagnostics map[string]string) string {
	parts := make([]string, 0, 5)
	for _, name := range []string{"app_version", "platform", "os_version", "locale", "screen"} {
		if value := diagnostics[name]; value != "" {
			parts = append(parts, value)
		}
	}
	return strings.Join(parts, " · ")
}

// shortThreadReference is the case number a rider can quote: the first segment
// of the thread UUID. It is a lookup prefix, not an identifier — ops resolve it
// with a prefix match — which is why nothing keys on it. Ids always come from
// newUUIDv4, so the hyphen is always there; a value without one is returned
// whole rather than cut at a guessed width.
func shortThreadReference(threadID string) string {
	if index := strings.IndexByte(threadID, '-'); index > 0 {
		return threadID[:index]
	}
	return threadID
}

func truncateRunes(value string, limit int) string {
	if utf8.RuneCountInString(value) <= limit {
		return value
	}
	runes := []rune(value)
	return string(runes[:limit-1]) + "…"
}
