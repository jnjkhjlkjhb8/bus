package main

import (
	"context"
	"encoding/json"
	"strings"
)

// railShapeRow is one TDX Rail/Shape element (TRA, THSR, or metro): the raw
// WKT geometry for one line, plus the identity/name fields carried alongside
// it. LineNo is absent from the THSR payload, so it is decoded but unused.
type railShapeRow struct {
	LineNo   string `json:"LineNo"`
	LineID   string `json:"LineID"`
	LineName struct {
		ZhTw string `json:"Zh_tw"`
		En   string `json:"En"`
	} `json:"LineName"`
	Geometry        string `json:"Geometry"`
	EncodedPolyline string `json:"EncodedPolyline"`
	UpdateTime      string `json:"UpdateTime"`
}

// isValidRailShapeWKT is a cheap shape check on the raw TDX WKT string before
// it ever reaches ST_GeomFromText: PostgreSQL parses/validates the geometry
// server-side, but a parse error there would fail the whole upsert
// transaction, not just the offending row. This catches the gross defects
// (empty string, missing parens, wrong geometry type) so a single bad row is
// quarantined instead of losing the whole partition's shapes.
func isValidRailShapeWKT(wkt string) bool {
	t := strings.ToUpper(strings.TrimSpace(wkt))
	if !strings.Contains(t, "(") || !strings.HasSuffix(t, ")") {
		return false
	}
	return strings.HasPrefix(t, "LINESTRING") || strings.HasPrefix(t, "MULTILINESTRING")
}

// loadRailShape returns a loader transform for one rail_shapes mode
// ("tra", "thsr", or "metro"). part is "" for the unpartitioned TRA/THSR
// datasets and the metro system code (TRTC/KRTC/...) for metro.
func loadRailShape(mode string) func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
	return func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
		return loadRailShapePart(ctx, dec, sink, mode, part)
	}
}

func loadRailShapePart(ctx context.Context, dec *json.Decoder, sink loadSink, mode, part string) error {
	shapes, err := decodeLoadArray[railShapeRow](dec, mode+"_shape", nil)
	if err != nil {
		return err
	}
	system := ""
	if mode == "metro" {
		system = part
	}
	row := [][]any{}
	seen := make(map[string][]any, len(shapes))
	for i, shape := range shapes {
		lineID := strings.TrimSpace(shape.LineID)
		if lineID == "" {
			log.Warnf("[LOAD] action=rail_shape event=skip reason=empty_line_id mode=%s system=%s index=%d", mode, system, i)
			continue
		}
		if !isValidRailShapeWKT(shape.Geometry) {
			log.Warnf("[LOAD] action=rail_shape event=skip reason=invalid_geometry mode=%s system=%s line_id=%s index=%d", mode, system, lineID, i)
			continue
		}
		nameJSON, err := json.Marshal(shape.LineName)
		if err != nil {
			log.Warnf("[LOAD] action=rail_shape event=skip reason=name_marshal_error mode=%s system=%s line_id=%s error=%v", mode, system, lineID, err)
			continue
		}
		candidate := []any{mode, system, lineID, string(nameJSON), shape.Geometry, shape.UpdateTime}
		key := mode + "/" + system + "/" + lineID
		if err := appendUniqueLoadRow(&row, seen, key, "line_id", candidate); err != nil {
			log.Warnf("[LOAD] action=rail_shape event=skip reason=%v mode=%s system=%s", err, mode, system)
			continue
		}
	}
	if len(row) == 0 {
		log.Infof("[LOAD] action=rail_shape event=complete mode=%s system=%s reason=no_data", mode, system)
		return nil
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "rail_shape_" + mode,
		preExec: []copyUpsertStmt{
			{sql: "DELETE FROM rail_shapes WHERE mode=$1 AND system=$2", args: []any{mode, system}},
		},
		createSQL: `CREATE TEMP TABLE temp_rail_shape (
				mode text,
				system text,
				line_id text,
				line_name text,
				geom text,
				updated_at text
			) ON COMMIT DROP`,
		tempTable: "temp_rail_shape",
		copyCols:  []string{"mode", "system", "line_id", "line_name", "geom", "updated_at"},
		insertSQL: `INSERT INTO rail_shapes (mode, system, line_id, line_name, geom, updated_at)
			SELECT mode, system, line_id, line_name::jsonb, ST_GeomFromText(geom, 4326),
				NULLIF(updated_at, '')::timestamptz
			FROM temp_rail_shape
			ON CONFLICT (mode, system, line_id) DO UPDATE SET
				line_name = EXCLUDED.line_name,
				geom = EXCLUDED.geom,
				updated_at = EXCLUDED.updated_at`,
	}, row)
}
