package main

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// errFeedbackQuota reports that the installation has already opened as many
// threads as the trailing window allows. It is a normal outcome of a hostile
// or looping client, not a fault, so it never reaches Sentry.
var errFeedbackQuota = errors.New("feedback quota exhausted")

// feedbackQuota bounds one installation's threads inside feedbackQuotaWindow.
// It is set where a determined rider reporting several genuine problems in one
// commute never reaches it, but a stuck client cannot fill the table.
const (
	feedbackQuota       = 10
	feedbackQuotaWindow = 24 * time.Hour
)

type feedbackThreadRecord struct {
	ThreadID    string
	InstallID   string
	Category    string
	Body        string
	Diagnostics map[string]string
}

// feedbackStore writes rider reports. It shares firebaseDB — the pgx subset
// both stores need — rather than declaring an identical second interface.
type feedbackStore struct{ db firebaseDB }

func NewFeedbackStore(db *pgxpool.Pool) *feedbackStore { return &feedbackStore{db: db} }

// OpenThread writes a thread and its opening message as one statement, and
// returns when the thread was created.
//
// The quota is enforced inside the INSERT's WHERE rather than by a preceding
// SELECT, so two concurrent submissions from the same installation cannot both
// read an under-limit count and both write. When the quota is spent the thread
// CTE returns no row, the message CTE selecting from it writes nothing, and
// the outer SELECT finds nothing — which is what errFeedbackQuota reports.
func (s *feedbackStore) OpenThread(ctx context.Context, record feedbackThreadRecord, messageID string) (time.Time, error) {
	diagnostics, err := json.Marshal(record.Diagnostics)
	if err != nil {
		return time.Time{}, err
	}
	var createdAt time.Time
	err = s.db.QueryRow(ctx, `
		WITH thread AS (
			INSERT INTO feedback_thread (id, install_id, category, diagnostics)
			SELECT $1, $2, $3, $4::jsonb
			WHERE (
				SELECT count(*) FROM feedback_thread
				WHERE install_id = $2
				  AND created_at > now() - ($5::double precision * interval '1 second')
			) < $6
			RETURNING id, created_at
		),
		message AS (
			INSERT INTO feedback_message (id, thread_id, author, body)
			SELECT $7, thread.id, 'user', $8 FROM thread
		)
		SELECT created_at FROM thread
	`,
		record.ThreadID, record.InstallID, record.Category, diagnostics,
		feedbackQuotaWindow.Seconds(), feedbackQuota,
		messageID, record.Body,
	).Scan(&createdAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, errFeedbackQuota
	}
	if err != nil {
		return time.Time{}, err
	}
	return createdAt, nil
}
