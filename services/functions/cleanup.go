package main

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"go.uber.org/zap"
)

// retentionDB is the narrow Postgres exec seam the retention job needs.
// *pgxpool.Pool satisfies it structurally; unit tests drive the job through a
// pgxmock pool instead of a live database.
type retentionDB interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// _cleanupBatchSize bounds each retention DELETE so cleanup never holds a
// single very-large transaction/lock against a live table. It repeats until a
// batch comes back under this size (nothing left to delete) or ctx is
// canceled.
const _cleanupBatchSize = 5000

// batchDeleteOlderThan repeatedly deletes up to cleanupBatchSize rows from
// table matching cutoffColumn < NOW() - retention, checking ctx before every
// batch so a canceled run stops between batches instead of racing to finish
// or blocking a single oversized DELETE. ctid selection (rather than an id
// column) works regardless of the table's primary key shape. Returns the
// total rows deleted so far even when it returns an error, since prior
// batches already committed.
func batchDeleteOlderThan(ctx context.Context, db retentionDB, table, cutoffColumn, retention string) (int64, error) {
	sql := fmt.Sprintf(`
		WITH victims AS (
			SELECT ctid FROM %s WHERE %s < NOW() - INTERVAL '%s' LIMIT $1
		)
		DELETE FROM %s WHERE ctid IN (SELECT ctid FROM victims)`,
		table, cutoffColumn, retention, table)

	var total int64
	for {
		if err := ctx.Err(); err != nil {
			return total, err
		}
		tag, err := db.Exec(ctx, sql, _cleanupBatchSize)
		if err != nil {
			return total, err
		}
		total += tag.RowsAffected()
		if tag.RowsAffected() < _cleanupBatchSize {
			return total, nil
		}
	}
}

// cleanupPredictionErrors deletes bus_eta_prediction_error rows older than 30
// days in capped batches rather than one unbounded DELETE. It is the only
// retention job left on Postgres: bus_eta_history moved to the MySQL history
// host, where it is kept indefinitely rather than pruned, so nothing deletes it.
func cleanupPredictionErrors(ctx context.Context, db retentionDB) error {
	deleted, err := batchDeleteOlderThan(ctx, db, "bus_eta_prediction_error", "predicted_at", "30 days")
	if err != nil {
		// deleted is the count from the batches that did land before the failure.
		return obs.Transient(_oops.With("deleted", deleted).Wrapf(err, "cleanup prediction error after rows"))
	}
	zap.S().Infow("cleanup deleted rows", "component", "eta_error", "rows", deleted)
	return nil
}
