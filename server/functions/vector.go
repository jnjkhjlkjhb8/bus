package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// busSubroutes is a bus subroute row scanned for embedding-text construction.
type busSubroutes struct {
	SubRouteUid  string `db:"sub_route_uid"`
	SubRouteName string `db:"sub_route_name"`
	City         string `db:"city"`
	Departure    string `db:"depart"`
	Destination  string `db:"destin"`
}

// busStationData is a bus station-group row shape for embedding-text construction.
type busStationData struct {
	StationUid  string `db:"station_uid"`
	StationName string `db:"station_name"`
	City        string `db:"city"`
	Geom        string `db:"st_astext"`
}

// bikeStationData is a bike station row shape for embedding-text construction.
type bikeStationData struct {
	StationUid  string `db:"station_uid"`
	StationName string `db:"name"`
	City        string `db:"city"`
	Position    string `db:"st_astext"`
}

// mrtStationData is a metro station row shape for embedding-text construction.
type mrtStationData struct {
	Position  string `db:"st_astext"`
	System    string `db:"system"`
	Name      string `db:"name"`
	StationId string `db:"station_id"`
}

// railStationData is a TRA/THSR station row shape for embedding-text construction.
type railStationData struct {
	StationId string `db:"station_id"`
	Name      string `db:"name"`
	City      string `db:"city"`
	Geom      string `db:"st_astext"`
}

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

// mrtSystemNames maps a metro system code to its Chinese display name for the
// embedding text.
var mrtSystemNames = map[string]string{
	"TRTC": "台北捷運", "KRTC": "高雄捷運", "KLRT": "桃園捷運",
	"TYMC": "台中捷運", "NTDLRT": "淡海輕軌", "KHLRT": "高雄輕軌",
}

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

// size is the embedding batch size: rows are accumulated to this many before one
// call to the embedding service and one DB batch upsert.
const size = 1024

// Per-entity queries selecting rows that need (re-)embedding: updated since the
// last run and not already present with an identical, non-null embedding (the
// freshness skip built by freshVectorSkipSQL). $1 is the since timestamp.
var (
	busSubroutesForVectorSQL = `
	SELECT bs.sub_route_uid, bs.sub_route_name, bs.city, bs.depart, bs.destin
	FROM bus_static bs
	WHERE bs.updated_at >= $1` + freshVectorSkipSQL("bus_route", "bs.sub_route_uid",
		"sv.name = bs.sub_route_name AND sv.depart = bs.depart AND sv.destin = bs.destin") + `;`
	busStationsForVectorSQL = `
	SELECT bg.group_uid, bg.group_name, bg.city, ST_AsText(bg.position)
	FROM bus_station_groups bg
	WHERE bg.updated_at >= $1` + freshVectorSkipSQL("bus_station", "bg.group_uid",
		"sv.name = bg.group_name AND ST_OrderingEquals(sv.geom, bg.position)") + `;`
	bikeStationsForVectorSQL = `
	SELECT bs.station_uid, bs.name, bs.city, ST_AsText(bs.geom)
	FROM bike_stations bs
	WHERE bs.updated_at >= $1` + freshVectorSkipSQL("bike_station", "bs.station_uid",
		"sv.name = bs.name AND ST_OrderingEquals(sv.geom, bs.geom)") + `;`
	mrtStationsForVectorSQL = `
	SELECT ms.station_id, ms.name, ms.system, ST_AsText(ms.stationposition)
	FROM mrt_station ms
	WHERE ms.updated_at >= $1` + freshVectorSkipSQL("mrt_station", "ms.station_id",
		"sv.name = ms.name AND ST_OrderingEquals(sv.geom, ms.stationposition)") + `;`
	thsrStationsForVectorSQL = `
	SELECT ts.station_id, ts.name, ts.city, ST_AsText(ts.geom)
	FROM thsr_stations ts
	WHERE ts.updated_at >= $1` + freshVectorSkipSQL("thsr_station", "ts.station_id",
		"sv.name = ts.name AND ST_OrderingEquals(sv.geom, ts.geom)") + `;`
	traStationsForVectorSQL = `
	SELECT ts.station_id, ts.name, ts.city, ST_AsText(ts.geom)
	FROM tra_stations ts
	WHERE ts.updated_at >= $1` + freshVectorSkipSQL("tra_station", "ts.station_id",
		"sv.name = ts.name AND ST_OrderingEquals(sv.geom, ts.geom)") + `;`
)

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

// changetovector refreshes the search_vector embeddings powering offline search.
// For each entity table it selects rows changed since the last run, builds a
// descriptive Chinese text per row, embeds them in batches of size via the
// embedding service, and upserts the vectors into search_vector. The
// "LastTimeUpdate" watermark in Redis only advances if every table succeeded, so
// a partial failure re-processes from the same point next run. No-op when no
// embedding endpoint is configured (EMBED_URL).
func changetovector(ctx context.Context, rc *redis.Client, db *pgxpool.Pool) {
	if embeddingURL() == "" {
		log.Infof("[vector] action=vector event=skip reason=embedding_disabled")
		return
	}
	since, _ := rc.Get("LastTimeUpdate").Result()
	if since == "" {
		since = time.Time{}.Format(time.RFC3339)
	}
	tables := []string{"bus_subroutes", "bus_station_groups", "bike_stations", "mrt_station", "tra_stations", "thsr_stations"}
	processBatch := func(table string, input []string, inrow []resp) bool {
		if len(input) == 0 {
			return true
		}
		body, comp, err, flipopen := callOllama(input)
		if err != nil || !comp {
			log.Infof("[vector] action=vector event=skip reason=api_error,error=%s", err)
			return false
		}
		var result struct {
			Embeddings [][]float32 `json:"embeddings"`
		}
		if err := json.Unmarshal(body, &result); err != nil {
			log.Infof("[vector] action=vector event=unmarshal_error error=%v", err)
			flipopen()
			return false
		}
		flipopen()
		resp := result.Embeddings
		b := &pgx.Batch{}
		c1 := `INSERT INTO search_vector(
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
		for i, v := range resp {
			d := inrow[i]
			b.Queue(c1, d.Type, d.UID, d.Name, d.City, d.DepartSystem, d.Destin, d.Geom, toVecLiteral(v))
		}
		batchResults := db.SendBatch(ctx, b)
		if err := batchResults.Close(); err != nil {
			log.Infof("[vector] action=vector event=batch_error error=%v", err)
			return false
		}
		log.Infof("[vector] action=vector event=success table=%s count=%d", table, len(resp))
		return true
	}
	failed := false
	for _, table := range tables {
		if failed {
			break
		}
		func() {
			switch table {
			case "bus_subroutes":
				rows, _ := db.Query(ctx, busSubroutesForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, city, depart, destin string
					if err := rows.Scan(&uid, &name, &city, &depart, &destin); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := cityName(city)
					text := fmt.Sprintf("類型：公車路線 子路線UID：%s 路線名：%s 縣市：%s 起點站：%s 終點站：%s", uid, name, cn, depart, destin)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "bus_route", UID: uid, Name: name, City: cn, DepartSystem: depart, Destin: destin})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			case "bus_station_groups":
				rows, _ := db.Query(ctx, busStationsForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, city, geom string
					if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := cityName(city)
					text := fmt.Sprintf("類型：公車組站位 組站位UID：%s 組站位名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "bus_station", UID: uid, Name: name, City: cn, Geom: geom})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			case "bike_stations":
				rows, _ := db.Query(ctx, bikeStationsForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, city, geom string
					if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := cityName(city)
					text := fmt.Sprintf("類型：公共自行車租借站 站點UID：%s 站點名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "bike_station", UID: uid, Name: name, City: cn, Geom: geom})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			case "mrt_station":
				rows, _ := db.Query(ctx, mrtStationsForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, system, geom string
					if err := rows.Scan(&uid, &name, &system, &geom); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := mrtSystemName(system)
					text := fmt.Sprintf("類型：捷運站 車站UID：%s 車站名稱：%s 捷運系統：%s 位置：%s", uid, name, cn, geom)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "mrt_station", UID: uid, Name: name, City: cn, Geom: geom})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			case "thsr_stations":
				rows, _ := db.Query(ctx, thsrStationsForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, city, geom string
					if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := cityName(city)
					text := fmt.Sprintf("類型：高鐵車站 車站UID：%s 車站名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "thsr_station", UID: uid, Name: name, City: cn, Geom: geom})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			case "tra_stations":
				rows, _ := db.Query(ctx, traStationsForVectorSQL, since)
				defer rows.Close()
				input := make([]string, 0, size)
				inrow := make([]resp, 0, size)
				for rows.Next() {
					var uid, name, city, geom string
					if err := rows.Scan(&uid, &name, &city, &geom); err != nil {
						log.Infof("[vector] action=vector event=scan_error error=%v", err)
						continue
					}
					cn := cityName(city)
					text := fmt.Sprintf("類型：台鐵車站 車站UID：%s 車站名稱：%s 縣市：%s 位置：%s", uid, name, cn, geom)
					input = append(input, text)
					inrow = append(inrow, resp{Type: "tra_station", UID: uid, Name: name, City: cn, Geom: geom})
					if len(input) >= size {
						if !processBatch(table, input, inrow) {
							failed = true
							return
						}
						input = input[:0]
						inrow = inrow[:0]
					}
				}
				if !processBatch(table, input, inrow) {
					failed = true
					return
				}
			}
		}()
	}
	if failed {
		log.Infof("[vector] action=vector event=incomplete last_time_update=unchanged")
		return
	}
	rc.Set("LastTimeUpdate", time.Now().Format(time.RFC3339), 0)
	log.Infof("[vector] action=vector event=complete")
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

// callOllama sends a batch of texts to the Ollama-compatible embedding endpoint
// (model qwen3-embedding:0.6b) and returns the raw response body. The bool is
// false with no error when no endpoint is configured. The returned func closes
// the response body and must be called when the bool is true.
func callOllama(input []string) ([]byte, bool, error, func()) {
	url := embeddingURL()
	if url == "" {
		return nil, false, nil, nil
	}
	client := resty.New().SetHeader("Content-Type", "application/json")
	resp, err := client.R().
		SetBody(map[string]interface{}{
			"model": "qwen3-embedding:0.6b",
			"input": input,
		}).
		Post(url)
	if err != nil {
		return nil, false, err, nil
	}
	return resp.Body(), true, nil, func() {
		if err := resp.RawResponse.Body.Close(); err != nil {
			log.Infof("[embed] action=fail-close-response error=%v", err)
		}
	}
}
