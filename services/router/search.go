package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
)

const (
	maxSearchQueryRunes  = 128
	searchRequestTimeout = 5 * time.Second

	// textSearchBranchCap bounds how many rows each UNION ALL branch in
	// textSearchSQL may return before ranking/dedup, independent of the
	// caller's requested result limit. This keeps every branch a capped,
	// indexable scan instead of one unbounded all-fields OR predicate.
	textSearchBranchCap = 200

	// textSearchBranchScale sizes the per-branch cap relative to the
	// caller's limit so small requests don't pull textSearchBranchCap rows
	// per branch; it's clamped to textSearchBranchCap either way.
	textSearchBranchScale = 5
)

// textSearchSQL splits exact, prefix/trigram, and contains matching into
// separate capped UNION ALL branches instead of one all-fields OR predicate.
// The exact branch (uid = $1) stays a single indexable equality predicate.
// Ranking (CASE) and trigram similarity are computed once over the unioned
// candidates; textSearch deduplicates by (type, uid) and applies the final
// result cap in Go so exactly one place enforces it.
const textSearchSQL = `
SELECT type, uid, name, city, depart, destin, ST_Y(geom), ST_X(geom),
       CASE
         WHEN uid = $1 THEN 0
         WHEN name = $1 THEN 1
         WHEN name ILIKE $1 || '%' THEN 2
         WHEN name % $1 THEN 3
         WHEN depart ILIKE '%' || $1 || '%'
           OR destin ILIKE '%' || $1 || '%' THEN 4
         ELSE 5
       END AS rank,
       similarity(name, $1) AS sim
FROM (
    SELECT type, uid, name, city, depart, destin, geom
    FROM search_vector
    WHERE uid = $1
    LIMIT $2
  UNION ALL
    SELECT type, uid, name, city, depart, destin, geom
    FROM search_vector
    WHERE name ILIKE $1 || '%' OR name % $1
    LIMIT $2
  UNION ALL
    SELECT type, uid, name, city, depart, destin, geom
    FROM search_vector
    WHERE name ILIKE '%' || $1 || '%'
       OR depart ILIKE '%' || $1 || '%'
       OR destin ILIKE '%' || $1 || '%'
    LIMIT $2
) candidates
ORDER BY rank, sim DESC, name ASC`

// textSearchBranchLimit bounds the per-branch row cap in textSearchSQL. It
// scales with the caller's requested limit so small requests scan less, but
// never exceeds textSearchBranchCap regardless of the requested limit.
func textSearchBranchLimit(limit int) int {
	if limit <= 0 {
		return 0
	}
	if scaled := limit * textSearchBranchScale; scaled > 0 && scaled < textSearchBranchCap {
		return scaled
	}
	return textSearchBranchCap
}

type searchDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

type searchResult struct {
	Type   string   `json:"type"`
	UID    string   `json:"uid"`
	Name   string   `json:"name"`
	City   string   `json:"city"`
	Depart string   `json:"depart"`
	Destin string   `json:"destin"`
	Lat    *float64 `json:"lat"`
	Lon    *float64 `json:"lon"`
}

func toVecLiteral(v []float32) string {
	parts := make([]string, len(v))
	for i, f := range v {
		parts[i] = strconv.FormatFloat(float64(f), 'f', -1, 32)
	}
	return "[" + strings.Join(parts, ",") + "]"
}

func embeddingURL() string {
	return strings.TrimSpace(os.Getenv("EMBED_URL"))
}

func embedQuery(ctx context.Context, text string) ([]float32, error) {
	url := embeddingURL()
	if url == "" {
		return nil, fmt.Errorf("embedding disabled")
	}
	ctx, cancel := context.WithTimeout(ctx, searchRequestTimeout)
	defer cancel()
	client := resty.New().SetHeader("Content-Type", "application/json")
	resp, err := client.R().
		SetContext(ctx).
		SetBody(map[string]interface{}{
			"model": "qwen3-embedding:0.6b",
			"input": []string{text},
		}).
		Post(url)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, err
	}
	if resp.StatusCode() != 200 {
		return nil, fmt.Errorf("embed %d: %s", resp.StatusCode(), resp.Body())
	}
	var result struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.Unmarshal(resp.Body(), &result); err != nil || len(result.Embeddings) == 0 {
		return nil, fmt.Errorf("embed parse: %v", err)
	}
	return result.Embeddings[0], nil
}

func vectorSearch(ctx context.Context, q string, limit int, db searchDB) ([]searchResult, error) {
	if embeddingURL() == "" {
		return nil, nil
	}
	vec, embedErr := embedQuery(ctx, q)
	if embedErr != nil {
		return nil, embedErr
	}
	rows, err := db.Query(ctx, `
		SELECT type, uid, name, city, depart, destin,
		       ST_Y(geom), ST_X(geom)
		FROM search_vector
		ORDER BY embedding <=> $1::vector
		LIMIT $2`,
		toVecLiteral(vec), limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var results []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err != nil {
			return nil, err
		}
		results = append(results, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

// textSearchCandidate pairs a scanned row with the rank/similarity the
// database computed for it, so textSearch can dedupe and order candidates
// that the same row may have reached through more than one SQL branch.
type textSearchCandidate struct {
	result searchResult
	rank   int
	sim    float64
}

func textSearch(ctx context.Context, q string, limit int, db searchDB) ([]searchResult, error) {
	rows, err := db.Query(ctx, textSearchSQL, q, textSearchBranchLimit(limit))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var candidates []textSearchCandidate
	for rows.Next() {
		var c textSearchCandidate
		if err := rows.Scan(
			&c.result.Type, &c.result.UID, &c.result.Name, &c.result.City,
			&c.result.Depart, &c.result.Destin, &c.result.Lat, &c.result.Lon,
			&c.rank, &c.sim,
		); err != nil {
			return nil, err
		}
		candidates = append(candidates, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return dedupeTextSearchCandidates(candidates, limit), nil
}

// dedupeTextSearchCandidates orders candidates by rank, then similarity, then
// name — matching the original single-query ORDER BY — before collapsing
// duplicate (type, uid) hits from separate UNION ALL branches to their
// best-ranked occurrence and applying the one final result cap.
func dedupeTextSearchCandidates(candidates []textSearchCandidate, limit int) []searchResult {
	if limit <= 0 {
		return nil
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].rank != candidates[j].rank {
			return candidates[i].rank < candidates[j].rank
		}
		if candidates[i].sim != candidates[j].sim {
			return candidates[i].sim > candidates[j].sim
		}
		return candidates[i].result.Name < candidates[j].result.Name
	})
	seen := make(map[string]bool, len(candidates))
	results := make([]searchResult, 0, limit)
	for _, c := range candidates {
		key := searchResultKey(c.result)
		if seen[key] {
			continue
		}
		seen[key] = true
		results = append(results, c.result)
		if len(results) >= limit {
			break
		}
	}
	return results
}

func searchResultKey(r searchResult) string {
	return r.Type + ":" + r.UID
}

func mergeSearchResults(limit int, groups ...[]searchResult) []searchResult {
	if limit <= 0 {
		return nil
	}
	seen := make(map[string]bool)
	merged := make([]searchResult, 0, limit)
	for _, group := range groups {
		for _, r := range group {
			key := searchResultKey(r)
			if seen[key] {
				continue
			}
			seen[key] = true
			merged = append(merged, r)
			if len(merged) >= limit {
				return merged
			}
		}
	}
	return merged
}

func expandStationRoutes(ctx context.Context, primary []searchResult, db searchDB) ([]searchResult, error) {
	var groupUIDs []string
	seen := make(map[string]bool)
	for _, r := range primary {
		seen[searchResultKey(r)] = true
		if r.Type == "bus_station" {
			groupUIDs = append(groupUIDs, r.UID)
		}
	}
	if len(groupUIDs) == 0 {
		return primary, nil
	}
	rows, err := db.Query(ctx, `
		SELECT sv.type, sv.uid, sv.name, sv.city, sv.depart, sv.destin,
		       ST_Y(sv.geom), ST_X(sv.geom)
		FROM bus_station_group_members bsgm
		JOIN bus_station_stop_map bssm
		  ON bssm.station_id = bsgm.station_uid
		JOIN search_vector sv
		  ON sv.uid = bssm.sub_route_uid AND sv.type = 'bus_route'
		WHERE bsgm.group_uid = ANY($1)`,
		groupUIDs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var extra []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err != nil {
			return nil, err
		}
		key := searchResultKey(r)
		if !seen[key] {
			extra = append(extra, r)
			seen[key] = true
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return append(primary, extra...), nil
}

func isNumericQuery(q string) bool {
	if len(q) == 0 {
		return false
	}
	for _, c := range q {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func shouldUseVector(q string) bool {
	return len([]rune(q)) >= 2 && !isNumericQuery(q)
}

func trainNumberSearch(ctx context.Context, q string, db searchDB) ([]searchResult, error) {
	rows, err := db.Query(ctx, `
		SELECT type, uid, name, city, depart, destin,
		       ST_Y(geom), ST_X(geom)
		FROM search_vector
		WHERE uid = $1 AND type IN ('tra_train', 'thsr_train')`,
		q,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var results []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err != nil {
			return nil, err
		}
		results = append(results, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func handleSearch(db searchDB) gin.HandlerFunc {
	return func(c *gin.Context) {
		q := strings.TrimSpace(c.Query("q"))
		if len(q) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "q required"})
			return
		}
		if utf8.RuneCountInString(q) > maxSearchQueryRunes {
			c.JSON(http.StatusBadRequest, gin.H{"error": "q too long"})
			return
		}
		limit := 20
		if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 && l <= 50 {
			limit = l
		}
		ctx, cancel := context.WithTimeout(c.Request.Context(), searchRequestTimeout)
		defer cancel()
		var trainResults []searchResult
		if isNumericQuery(q) {
			var err error
			trainResults, err = trainNumberSearch(ctx, q, db)
			if err != nil {
				log.Errorf("[SEARCH] train number search failed: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
				return
			}
		}
		textResults, err := textSearch(ctx, q, limit, db)
		if err != nil {
			log.Errorf("[SEARCH] error: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
			return
		}
		results := mergeSearchResults(limit, trainResults, textResults)
		// ponytail: semantic fallback only when text search found nothing —
		// the embedQuery call + vector scan are expensive; skip them whenever
		// trigram/ILIKE already matched. Loosen this if typo-tolerance suffers.
		if len(results) == 0 && shouldUseVector(q) {
			vectorResults, err := vectorSearch(ctx, q, limit, db)
			if err != nil {
				log.Errorf("[SEARCH] vector search failed: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
				return
			}
			results = mergeSearchResults(limit, results, vectorResults)
		}
		expandedResults, err := expandStationRoutes(ctx, results, db)
		if err != nil {
			log.Errorf("[SEARCH] route expansion failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
			return
		}
		results = mergeSearchResults(limit, expandedResults)
		c.JSON(http.StatusOK, gin.H{"results": results})
	}
}
