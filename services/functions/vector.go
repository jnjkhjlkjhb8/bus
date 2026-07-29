package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
)

// resp is the metadata for one item being embedded, carried alongside its input
// text so the resulting embedding can be upserted into search_vector with the
// right identity. DepartSystem holds the departure stop for buses or the transit
// system for rail/metro.
type resp struct {
	Type         string
	UID          string
	Name         string
	City         string
	DepartSystem string
	Destin       string
	Geom         string
	postUpsert   []vectorWrite
}

type vectorWrite struct {
	sql  string
	args []interface{}
}

// cityNames maps a TDX city code to its Chinese display name, embedded into the
// search text so name queries match on locality.
var cityNames = map[string]string{
	"Taipei": "台北市", "NewTaipei": "新北市", "Taoyuan": "桃園市",
	"Taichung": "台中市", "Tainan": "台南市", "Kaohsiung": "高雄市",
	"Keelung": "基隆市", "Hsinchu": "新竹市", "HsinchuCounty": "新竹縣",
	"MiaoliCounty": "苗栗縣", "ChanghuaCounty": "彰化縣", "NantouCounty": "南投縣",
	"YunlinCounty": "雲林縣", "ChiayiCounty": "嘉義縣", "Chiayi": "嘉義市",
	"PingtungCounty": "屏東縣", "YilanCounty": "宜蘭縣", "HualienCounty": "花蓮縣",
	"TaitungCounty": "台東縣", "PenghuCounty": "澎湖縣",
	"KinmenCounty": "金門縣", "LienchiangCounty": "連江縣",
	"InterCity": "公路客運",
	"Miaoli":    "苗栗縣", "Changhua": "彰化縣", "Nantou": "南投縣",
	"Yunlin": "雲林縣", "Pingtung": "屏東縣", "Yilan": "宜蘭縣",
	"Hualien": "花蓮縣", "Taitung": "台東縣", "Penghu": "澎湖縣",
	"Kinmen": "金門縣", "Lienchiang": "連江縣",
}

type mrtSystemLabel struct {
	code    string
	current string
	legacy  []string
}

// mrtSystemLabels is the single source for both embedding labels and the SQL
// revision checks that invalidate vectors created with an older label mapping.
var mrtSystemLabels = []mrtSystemLabel{
	{code: "TRTC", current: "台北捷運"},
	{code: "KRTC", current: "高雄捷運"},
	{code: "KLRT", current: "高雄輕軌", legacy: []string{"桃園捷運"}},
	{code: "TYMC", current: "桃園捷運", legacy: []string{"台中捷運"}},
	{code: "NTMC", current: "新北捷運", legacy: []string{"NTMC"}},
	{code: "NTDLRT", current: "淡海輕軌"},
	{code: "KHLRT", current: "高雄輕軌"},
}

// mrtSystemNames maps a metro system code to its Chinese display name for the
// embedding text.
var mrtSystemNames = func() map[string]string {
	names := make(map[string]string, len(mrtSystemLabels))
	for _, label := range mrtSystemLabels {
		names[label.code] = label.current
	}
	return names
}()

// cityName returns the Chinese display name for a city code, or the code itself
// when unmapped.
func cityName(code string) string {
	if n, ok := cityNames[code]; ok {
		return n
	}
	return code
}

// mrtSystemName returns the Chinese display name for a metro system code, or the
// code itself when unmapped.
func mrtSystemName(code string) string {
	if n, ok := mrtSystemNames[code]; ok {
		return n
	}
	return code
}

func sqlStringLiteral(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

func mrtSystemNameSQL(systemExpr string) string {
	var sql strings.Builder
	sql.WriteString("CASE ")
	sql.WriteString(systemExpr)
	for _, label := range mrtSystemLabels {
		sql.WriteString(" WHEN ")
		sql.WriteString(sqlStringLiteral(label.code))
		sql.WriteString(" THEN ")
		sql.WriteString(sqlStringLiteral(label.current))
	}
	sql.WriteString(" ELSE ")
	sql.WriteString(systemExpr)
	sql.WriteString(" END")
	return sql.String()
}

func mrtVectorSamePredicate(vectorAlias, stationAlias string) string {
	return fmt.Sprintf(
		"%[1]s.name = %[2]s.name AND %[1]s.city = %[3]s AND %[1]s.depart = %[2]s.system AND ST_OrderingEquals(%[1]s.geom, %[2]s.stationposition)",
		vectorAlias,
		stationAlias,
		mrtSystemNameSQL(stationAlias+".system"),
	)
}

func buildMRTStationsForVectorSQL() string {
	return `
	SELECT ms.station_id, ms.name, ms.system, ST_AsText(ms.stationposition)
	FROM mrt_station ms
	WHERE ms.updated_at < $1` + freshVectorSkipSQL("mrt_station", "ms.station_id",
		mrtVectorSamePredicate("sv", "ms")) + `;`
}

func buildMRTLegacyVectorCleanupSQL() string {
	return fmt.Sprintf(`
	DELETE FROM search_vector stale_sv
	WHERE stale_sv.type = 'mrt_station'
	  AND stale_sv.uid = $1
	  AND stale_sv.city = $2
	  AND EXISTS (
	    SELECT 1
	    FROM mrt_station stale_ms
	    WHERE stale_ms.station_id = stale_sv.uid
	      AND stale_ms.system = $3
	  )
	  AND NOT EXISTS (
	    SELECT 1
	    FROM mrt_station keeper_ms
	    WHERE keeper_ms.station_id = stale_sv.uid
	      AND %s = stale_sv.city
	  );`, mrtSystemNameSQL("keeper_ms.system"))
}

func mrtLegacyVectorCleanupWrites(uid, system string) []vectorWrite {
	for _, label := range mrtSystemLabels {
		if label.code != system {
			continue
		}
		writes := make([]vectorWrite, 0, len(label.legacy))
		for _, legacy := range label.legacy {
			writes = append(writes, vectorWrite{
				sql:  mrtLegacyVectorCleanupSQL,
				args: []interface{}{uid, legacy, system},
			})
		}
		return writes
	}
	return nil
}

const (
	// size is the embedding batch size: rows are accumulated to this many before
	// one call to the embedding service and one DB batch upsert.
	size = 1024
	// embeddingDimension is fixed by the search_vector pgvector schema and the
	// configured qwen3-embedding model.
	embeddingDimension = 1024
)

type embeddingClient interface {
	Embed(context.Context, []string) ([][]float32, error)
}

type vectorDB interface {
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	SendBatch(context.Context, *pgx.Batch) pgx.BatchResults
}

type vectorRedis interface {
	Get(string) *redis.StringCmd
	Set(string, interface{}, time.Duration) *redis.StatusCmd
}

// Per-entity queries select rows not already present with an identical,
// non-null embedding (the freshness skip built by freshVectorSkipSQL). Most use
// the half-open watermark window; MRT checks all rows below the captured upper
// cutoff so code-only label revisions older than the lower watermark backfill.
var (
	busSubroutesForVectorSQL = `
	SELECT bs.sub_route_uid, bs.sub_route_name, bs.city, bs.depart, bs.destin
	FROM bus_static bs
	WHERE bs.updated_at >= $1 AND bs.updated_at < $2` + freshVectorSkipSQL("bus_route", "bs.sub_route_uid",
		"sv.name = bs.sub_route_name AND sv.depart = bs.depart AND sv.destin = bs.destin") + `;`
	busStationsForVectorSQL = `
	SELECT bg.group_uid, bg.group_name, bg.city, ST_AsText(bg.position)
	FROM bus_station_groups bg
	WHERE bg.updated_at >= $1 AND bg.updated_at < $2` + freshVectorSkipSQL("bus_station", "bg.group_uid",
		"sv.name = bg.group_name AND ST_OrderingEquals(sv.geom, bg.position)") + `;`
	bikeStationsForVectorSQL = `
	SELECT bs.station_uid, bs.name, bs.city, ST_AsText(bs.geom)
	FROM bike_stations bs
	WHERE bs.updated_at >= $1 AND bs.updated_at < $2` + freshVectorSkipSQL("bike_station", "bs.station_uid",
		"sv.name = bs.name AND ST_OrderingEquals(sv.geom, bs.geom)") + `;`
	mrtStationsForVectorSQL   = buildMRTStationsForVectorSQL()
	mrtLegacyVectorCleanupSQL = buildMRTLegacyVectorCleanupSQL()
	traStationsForVectorSQL   = `
	SELECT ts.station_id, ts.name, ts.city, ST_AsText(ts.geom)
	FROM tra_stations ts
	WHERE ts.updated_at >= $1 AND ts.updated_at < $2` + freshVectorSkipSQL("tra_station", "ts.station_id",
		"sv.name = ts.name AND ST_OrderingEquals(sv.geom, ts.geom)") + `;`
	thsrStationsForVectorSQL = `
	SELECT ts.station_id, ts.name, ts.city, ST_AsText(ts.geom)
	FROM thsr_stations ts
	WHERE ts.updated_at >= $1 AND ts.updated_at < $2` + freshVectorSkipSQL("thsr_station", "ts.station_id",
		"sv.name = ts.name AND ST_OrderingEquals(sv.geom, ts.geom)") + `;`
)

// vectorDataset keeps the query and row-to-embedding-input processor together,
// preventing the registry order from drifting away from dataset-specific scan
// and text construction behavior.
type vectorDataset struct {
	key        string
	vectorType string
	query      string
	queryArgs  func(string, interface{}) []interface{}
	process    func(pgx.Rows) (string, resp, error)
}

func watermarkWindowQueryArgs(lower string, upper interface{}) []interface{} {
	return []interface{}{lower, upper}
}

func upperCutoffQueryArgs(_ string, upper interface{}) []interface{} {
	return []interface{}{upper}
}

var vectorDatasets = []vectorDataset{
	{
		key:        "bus_subroutes",
		vectorType: "bus_route",
		query:      busSubroutesForVectorSQL,
		queryArgs:  watermarkWindowQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, city, depart, destin string
			if err := rows.Scan(&uid, &name, &city, &depart, &destin); err != nil {
				return "", resp{}, err
			}
			cn := cityName(city)
			text := fmt.Sprintf("類型：公車路線 子路線UID：%s 路線名：%s 縣市：%s 起點站：%s 終點站：%s", uid, name, cn, depart, destin)
			return text, resp{UID: uid, Name: name, City: cn, DepartSystem: depart, Destin: destin}, nil
		},
	},
	{
		key:        "bus_station_groups",
		vectorType: "bus_station",
		query:      busStationsForVectorSQL,
		queryArgs:  watermarkWindowQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, city, geom string
			if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
				return "", resp{}, err
			}
			cn := cityName(city)
			text := fmt.Sprintf("類型：公車組站位 組站位UID：%s 組站位名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
			return text, resp{UID: uid, Name: name, City: cn, Geom: geom}, nil
		},
	},
	{
		key:        "bike_stations",
		vectorType: "bike_station",
		query:      bikeStationsForVectorSQL,
		queryArgs:  watermarkWindowQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, city, geom string
			if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
				return "", resp{}, err
			}
			cn := cityName(city)
			text := fmt.Sprintf("類型：公共自行車租借站 站點UID：%s 站點名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
			return text, resp{UID: uid, Name: name, City: cn, Geom: geom}, nil
		},
	},
	{
		key:        "mrt_station",
		vectorType: "mrt_station",
		query:      mrtStationsForVectorSQL,
		queryArgs:  upperCutoffQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, system, geom string
			if err := rows.Scan(&uid, &name, &system, &geom); err != nil {
				return "", resp{}, err
			}
			cn := mrtSystemName(system)
			text := fmt.Sprintf("類型：捷運站 車站UID：%s 車站名稱：%s 捷運系統：%s 位置：%s", uid, name, cn, geom)
			return text, resp{
				UID:          uid,
				Name:         name,
				City:         cn,
				DepartSystem: system,
				Geom:         geom,
				postUpsert:   mrtLegacyVectorCleanupWrites(uid, system),
			}, nil
		},
	},
	{
		key:        "tra_stations",
		vectorType: "tra_station",
		query:      traStationsForVectorSQL,
		queryArgs:  watermarkWindowQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, city, geom string
			if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
				return "", resp{}, err
			}
			cn := cityName(city)
			text := fmt.Sprintf("類型：台鐵車站 車站UID：%s 車站名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
			return text, resp{UID: uid, Name: name, City: cn, Geom: geom}, nil
		},
	},
	{
		key:        "thsr_stations",
		vectorType: "thsr_station",
		query:      thsrStationsForVectorSQL,
		queryArgs:  watermarkWindowQueryArgs,
		process: func(rows pgx.Rows) (string, resp, error) {
			var uid, name, city, geom string
			if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
				return "", resp{}, err
			}
			cn := cityName(city)
			text := fmt.Sprintf("類型：高鐵車站 車站UID：%s 車站名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
			return text, resp{UID: uid, Name: name, City: cn, Geom: geom}, nil
		},
	},
}

// freshVectorSkipSQL builds a NOT EXISTS clause that skips rows already embedded
// with unchanged content, so a run only re-embeds new or changed entities.
// vectorType, uidExpr, and samePredicate are interpolated into SQL from
// package-constant call sites only — never from external input.
func freshVectorSkipSQL(vectorType, uidExpr, samePredicate string) string {
	return fmt.Sprintf(`
	  AND NOT EXISTS (
	    SELECT 1
	    FROM search_vector sv
	    WHERE sv.type = '%s'
	      AND sv.uid = %s
	      AND sv.embedding IS NOT NULL
	      AND %s
	  )`, vectorType, uidExpr, samePredicate)
}

const searchVectorUpsertSQL = `INSERT INTO search_vector(
			type, uid, name, city, depart, destin, geom, embedding, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6,
			CASE WHEN $7 = '' THEN NULL ELSE ST_GeomFromText($7, 4326) END,
			$8::vector, NOW())
		ON CONFLICT (type, uid, city)
		DO UPDATE SET name = EXCLUDED.name,
			depart = EXCLUDED.depart,
			destin = EXCLUDED.destin,
			geom = EXCLUDED.geom,
			embedding = EXCLUDED.embedding,
			updated_at = NOW();`

func processVectorBatch(ctx context.Context, db vectorDB, embedder embeddingClient, input []string, rows []resp) error {
	if len(input) == 0 {
		return nil
	}
	if len(rows) != len(input) {
		return fmt.Errorf("vector metadata count = %d, input count = %d", len(rows), len(input))
	}
	embeddings, err := embedder.Embed(ctx, input)
	if err != nil {
		return fmt.Errorf("embed vector batch: %w", err)
	}
	if len(embeddings) != len(input) {
		return fmt.Errorf("embedding count = %d, input count = %d", len(embeddings), len(input))
	}
	for i, embedding := range embeddings {
		if len(embedding) != embeddingDimension {
			return fmt.Errorf("embedding %d dimension = %d, want %d", i, len(embedding), embeddingDimension)
		}
	}

	batch := &pgx.Batch{}
	for i, embedding := range embeddings {
		row := rows[i]
		batch.Queue(searchVectorUpsertSQL,
			row.Type, row.UID, row.Name, row.City, row.DepartSystem,
			row.Destin, row.Geom, toVecLiteral(embedding))
		for _, write := range row.postUpsert {
			batch.Queue(write.sql, write.args...)
		}
	}
	// With no transaction-control statements, pgx executes the batch in an
	// implicit transaction. A cleanup failure therefore rolls back its preceding
	// replacement upsert, and an upsert failure prevents its cleanup from running.
	if err := db.SendBatch(ctx, batch).Close(); err != nil {
		return fmt.Errorf("write vector batch: %w", err)
	}
	return nil
}

func processVectorDataset(
	ctx context.Context,
	db vectorDB,
	embedder embeddingClient,
	dataset vectorDataset,
	lower string,
	upper time.Time,
) error {
	rows, err := db.Query(ctx, dataset.query, dataset.queryArgs(lower, upper)...)
	if err != nil {
		return fmt.Errorf("query vector dataset %s: %w", dataset.key, err)
	}
	defer rows.Close()

	input := make([]string, 0, size)
	metadata := make([]resp, 0, size)
	for rows.Next() {
		text, row, err := dataset.process(rows)
		if err != nil {
			return fmt.Errorf("scan vector dataset %s: %w", dataset.key, err)
		}
		row.Type = dataset.vectorType
		input = append(input, text)
		metadata = append(metadata, row)
		if len(input) == size {
			if err := processVectorBatch(ctx, db, embedder, input, metadata); err != nil {
				return fmt.Errorf("process vector dataset %s: %w", dataset.key, err)
			}
			input = input[:0]
			metadata = metadata[:0]
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("read vector dataset %s rows: %w", dataset.key, err)
	}
	if err := processVectorBatch(ctx, db, embedder, input, metadata); err != nil {
		return fmt.Errorf("process vector dataset %s: %w", dataset.key, err)
	}
	return nil
}

// changeToVector refreshes every registered search-vector dataset inside one
// half-open watermark window. It advances LastTimeUpdate to the captured upper
// cutoff only after all queries, scans, embeddings, and batch writes succeed.
func changeToVector(ctx context.Context, rc vectorRedis, db vectorDB, embedder embeddingClient) error {
	if embedder == nil {
		log.Warnf("[vector] action=vector event=skip reason=embedding_disabled")
		return nil
	}

	cutoff := time.Now().UTC()
	lower, err := rc.Get("LastTimeUpdate").Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return fmt.Errorf("get vector watermark: %w", err)
	}
	if lower == "" {
		lower = time.Time{}.Format(time.RFC3339)
	}

	for _, dataset := range vectorDatasets {
		if err := processVectorDataset(ctx, db, embedder, dataset, lower, cutoff); err != nil {
			return err
		}
	}
	watermark := cutoff.Format(time.RFC3339Nano)
	if err := rc.Set("LastTimeUpdate", watermark, 0).Err(); err != nil {
		return fmt.Errorf("set vector watermark: %w", err)
	}
	log.Infof("[vector] action=vector event=complete cutoff=%s", watermark)
	return nil
}

// toVecLiteral formats an embedding as a pgvector text literal (e.g. "[1,2,3]")
// for binding to a ::vector column.
func toVecLiteral(v []float32) string {
	parts := make([]string, len(v))
	for i, f := range v {
		parts[i] = strconv.FormatFloat(float64(f), 'f', -1, 32)
	}
	return "[" + strings.Join(parts, ",") + "]"
}

// embeddingURL returns the configured embedding endpoint (EMBED_URL), trimmed.
// An empty result means embeddings are disabled.
func embeddingURL() string {
	return strings.TrimSpace(os.Getenv("EMBED_URL"))
}

const embeddingHTTPTimeout = 2 * time.Minute

type httpEmbedder struct {
	url    string
	client *resty.Client
}

func newHTTPEmbedder(url string) *httpEmbedder {
	return &httpEmbedder{
		url: strings.TrimSpace(url),
		client: resty.New().
			SetHeader("Content-Type", "application/json").
			SetTimeout(embeddingHTTPTimeout),
	}
}

func configuredEmbeddingClient() embeddingClient {
	url := embeddingURL()
	if url == "" {
		return nil
	}
	return newHTTPEmbedder(url)
}

func (e *httpEmbedder) Embed(ctx context.Context, input []string) (embeddings [][]float32, err error) {
	if e == nil || e.url == "" {
		return nil, fmt.Errorf("embedding endpoint is disabled")
	}
	response, err := e.client.R().
		SetContext(ctx).
		SetDoNotParseResponse(true).
		SetBody(map[string]interface{}{
			"model": "qwen3-embedding:0.6b",
			"input": input,
		}).
		Post(e.url)
	if err != nil {
		return nil, fmt.Errorf("request embeddings: %w", err)
	}
	if response.RawResponse == nil || response.RawResponse.Body == nil {
		return nil, fmt.Errorf("embedding endpoint returned no response body")
	}
	defer func() {
		if closeErr := response.RawResponse.Body.Close(); err == nil && closeErr != nil {
			err = fmt.Errorf("close embedding response: %w", closeErr)
		}
	}()

	body, err := io.ReadAll(response.RawResponse.Body)
	if err != nil {
		return nil, fmt.Errorf("read embedding response: %w", err)
	}
	if !response.IsSuccess() {
		return nil, fmt.Errorf("embedding endpoint returned HTTP %d: %s", response.StatusCode(), strings.TrimSpace(string(body)))
	}
	var result struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("decode embedding response: %w", err)
	}
	return result.Embeddings, nil
}
