package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5/pgxpool"
)

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

func embedQuery(text string) ([]float32, error) {
	url := embeddingURL()
	if url == "" {
		return nil, fmt.Errorf("embedding disabled")
	}
	client := resty.New().SetHeader("Content-Type", "application/json")
	resp, err := client.R().
		SetBody(map[string]interface{}{
			"model": "qwen3-embedding:0.6b",
			"input": []string{text},
		}).
		Post(url)
	if err != nil {
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

func vectorSearch(ctx context.Context, q string, limit int, db *pgxpool.Pool) ([]searchResult, error) {
	if embeddingURL() == "" {
		return nil, nil
	}
	vec, embedErr := embedQuery(q)
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
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err == nil {
			results = append(results, r)
		}
	}
	return results, nil
}

func textSearch(ctx context.Context, q string, limit int, db *pgxpool.Pool) ([]searchResult, error) {
	rows, err := db.Query(ctx, `
		SELECT type, uid, name, city, depart, destin,
		       ST_Y(geom), ST_X(geom)
		FROM search_vector
		WHERE uid = $1
		   OR name ILIKE $1 || '%'
		   OR name % $1
		   OR name ILIKE '%' || $1 || '%'
		   OR depart ILIKE '%' || $1 || '%'
		   OR destin ILIKE '%' || $1 || '%'
		ORDER BY
		  CASE
		    WHEN uid = $1 THEN 0
		    WHEN name = $1 THEN 1
		    WHEN name ILIKE $1 || '%' THEN 2
		    WHEN name % $1 THEN 3
		    WHEN depart ILIKE '%' || $1 || '%'
		      OR destin ILIKE '%' || $1 || '%' THEN 4
		    ELSE 5
		  END,
		  similarity(name, $1) DESC,
		  name ASC
		LIMIT $2`,
		q, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var results []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err == nil {
			results = append(results, r)
		}
	}
	return results, nil
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

func expandStationRoutes(ctx context.Context, primary []searchResult, db *pgxpool.Pool) []searchResult {
	var groupUIDs []string
	seen := make(map[string]bool)
	for _, r := range primary {
		seen[searchResultKey(r)] = true
		if r.Type == "bus_station" {
			groupUIDs = append(groupUIDs, r.UID)
		}
	}
	if len(groupUIDs) == 0 {
		return primary
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
		log.Infof("[SEARCH] route expansion error: %v", err)
		return primary
	}
	defer rows.Close()
	var extra []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err == nil {
			key := searchResultKey(r)
			if !seen[key] {
				extra = append(extra, r)
				seen[key] = true
			}
		}
	}
	return append(primary, extra...)
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

func trainNumberSearch(ctx context.Context, q string, db *pgxpool.Pool) []searchResult {
	rows, err := db.Query(ctx, `
		SELECT type, uid, name, city, depart, destin,
		       ST_Y(geom), ST_X(geom)
		FROM search_vector
		WHERE uid = $1 AND type IN ('tra_train', 'thsr_train')`,
		q,
	)
	if err != nil {
		log.Infof("[SEARCH] train number search error: %v", err)
		return nil
	}
	defer rows.Close()
	var results []searchResult
	for rows.Next() {
		var r searchResult
		if err := rows.Scan(&r.Type, &r.UID, &r.Name, &r.City, &r.Depart, &r.Destin, &r.Lat, &r.Lon); err == nil {
			results = append(results, r)
		}
	}
	return results
}

func handleSearch(db *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		q := strings.TrimSpace(c.Query("q"))
		if len(q) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "q required"})
			return
		}
		limit := 20
		if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 && l <= 50 {
			limit = l
		}
		ctx := c.Request.Context()
		var trainResults []searchResult
		if isNumericQuery(q) {
			trainResults = trainNumberSearch(ctx, q, db)
		}
		textResults, err := textSearch(ctx, q, limit, db)
		if err != nil {
			log.Infof("[SEARCH] error: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
			return
		}
		results := mergeSearchResults(limit, trainResults, textResults)
		if len(results) < limit && shouldUseVector(q) {
			vectorResults, err := vectorSearch(ctx, q, limit, db)
			if err != nil {
				log.Infof("[SEARCH] vector supplement skipped: %v", err)
			} else {
				results = mergeSearchResults(limit, results, vectorResults)
			}
		}
		results = mergeSearchResults(limit, expandStationRoutes(ctx, results, db))
		c.JSON(http.StatusOK, gin.H{"results": results})
	}
}
