package raw

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/history"
	"go.uber.org/zap"
)

// raw_tdx_archive is the only record of what upstream actually said on a given
// day. raw_tdx itself is DELETEd/TRUNCATEd on every landing and TDX serves only
// "now", so an overwritten payload is unrecoverable; the archive keeps one row
// per distinct upstream version, payload verbatim.
//
// Verbatim, not parsed: the columns of raw_tdx.* are TDX's shape and drift
// whenever TDX adds a field, and a payload stored as-is can be replayed through
// the same insertRawChunks path that originally landed it. See ADR-0023.
var _rawArchiveCols = []string{"dataset", "partition_val", "last_modified", "landing_cycle", "fetched_at", "payload"}

// ArchivePayload stores one landed payload against its upstream version.
//
// uq_version (dataset, partition_val, last_modified) makes a forced refetch of
// an unchanged version a no-op at the database — archiveInsert's INSERT IGNORE
// absorbs it — so this is safe to call on every landing attempt rather than
// only on the ones that changed something.
//
// A failure here does NOT stop the landing (ADR-0023): it is logged and the
// caller proceeds. The cost is knowingly accepted and worth naming, because it
// is larger than it looks — the landing that follows overwrites the previous
// version, so one failed archive write loses both the version it failed to
// store and the one it would have replaced.
//
// db nil (ARCHIVE_MYSQL_DSN empty, which is every non-prod environment) is a
// silent no-op, the same contract as the other archive writers.
func ArchivePayload(
	ctx context.Context,
	db history.Execer,
	t Target,
	marker, landingCycle string,
	body io.ReadSeeker,
) {
	if db == nil || body == nil {
		return
	}
	payload, err := gzipAll(body)
	if err != nil {
		zap.S().Errorw("compress error", "component", "raw_archive", "table", t.Table, "partition", t.PartVal, "err", err)
		return
	}
	row := []any{t.Table, t.PartVal, marker, landingCycle, time.Now(), payload}
	if err := history.Insert(ctx, db, "raw_tdx_archive", _rawArchiveCols, [][]any{row}); err != nil {
		zap.S().Errorw("insert error", "component", "raw_archive", "table", t.Table, "partition", t.PartVal, "err", err)
		return
	}
	zap.S().Infow("archived payload",
		"component", "raw_archive",
		"table", t.Table,
		"partition", t.PartVal,
		"marker", marker,
		"bytes", len(payload),
	)
}

// gzipAll reads r to EOF and returns it gzipped, leaving r rewound for the
// caller.
//
// ponytail: the compressed payload is held whole in memory. The landing path
// deliberately streams to keep server-side parse memory bounded, but a gzip
// stream cannot be bound to a MySQL parameter without being finished first, and
// the largest datasets compress to a few MB of JSON. If a payload ever grows
// past what that assumption tolerates, the upgrade is a temp file, not a
// smarter buffer.
func gzipAll(r io.ReadSeeker) ([]byte, error) {
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return nil, _oops.Wrapf(err, "rewind payload")
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := io.Copy(zw, r); err != nil {
		return nil, _oops.Wrapf(err, "compress payload")
	}
	if err := zw.Close(); err != nil {
		return nil, _oops.Wrapf(err, "finish gzip stream")
	}
	// The landing retry loop rewinds before every attempt, but a reader left at
	// EOF is a trap for any future caller that does not.
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return nil, _oops.Wrapf(err, "rewind payload after compress")
	}
	return buf.Bytes(), nil
}
