# 架構說明

## 部署環境
```
Flutter App
    │
    ├─ gRPC :50051      → router
    ├─ HTTP :8080       → router (JWT / JWKS / embed)
    └─ HTTP :8081       → PowerSync (資料同步)

router / functions / powersync / motis / redis
    │
    └─ PostgreSQL（外部）
```

## 服務一覽

| 服務 | 映像 | 對外端口 | 記憶體上限 |
|---|---|---|---|
| redis | redis:7-alpine | 127.0.0.1:6379 | 512 MB |
| router | bus-router (Go) | 50051, 8080 | 256 MB |
| functions | bus-functions (Go) | — | 768 MB |
| ingestor | bus-functions (Go, `ROLE=ingestor`；TDX 憑證僅 prod，無憑證時直接跳過、零請求) | — | 384 MB |
| loader | bus-functions (Go, `ROLE=loader`) | — | 384 MB |
| powersync | journeyapps/powersync-service | 8081 | 384 MB |
| motis | ghcr.io/motis-project/motis | 127.0.0.1:8082 | 2048 MB |

MOTIS 的上限必須高於匯入後資料集的實際大小：`motis server`
是 mmap 讀取，cgroup 會把那些 page cache 算進容器帳上，上限低於資料量時每次
`/table` 查詢都要重新從磁碟讀 cell metrics。

Redis 與 MOTIS 僅對 localhost 開放，不對外暴露。MOTIS 的 8082 之所以要 publish，是因為 staging 的 router 在同一台主機的另一個 compose project 裡，需要經由 host gateway 連到 prod 的 MOTIS（ADR-0022）。

## 程式結構

- `services/worker`
  - 排程執行器；一個映像以 `ROLE` 環境變數分兩種模式：
    - `ROLE=ingestor`：Stage 1，03:00 把 TDX 原始 payload 落地共用 `raw_tdx` schema。容器每個環境都會啟動（只有 `make up-test` 不啟動），但 TDX 憑證只放在 prod；`ingestRaw` 在缺任一憑證時直接跳過整趟落地、不發出任何請求（真正的 no-op，只記一行 `event=idle reason=no_credentials`）。每趟落地都是 conditional GET，但週日的 03:00 會丟掉 If-Modified-Since marker 無條件重抓全部端點：TDX 若刪除資料而沒有推進 `Last-Modified`，只有全量重抓看得到。全量落地結束後會掃一次 `raw_tdx.landing_state`，把超過七天沒被碰過的分區記成 `event=stale_partition`（只回報，不刪除）。
    - `ROLE=""`（每個環境）：Stage 2 loader（03:30 `raw_tdx` → 該環境 `PG_SCHEMA`）＋ 即時 ETA ＋ MQTT ＋ 通知。
  - TDX MQTT 訂閱（`mqtt.go`），接收即時告警並推送至 Redis Pub/Sub
  - 使用 `robfig/cron` 設定排程（見 `docs/ingestion.md`）
  - pgxpool：MaxConns=10，MinConns=2，MaxConnLifetime=30m，MaxConnIdleTime=5m
  - Redis pool：PoolSize=20，MinIdleConns=3，PoolTimeout=5s
- `services/api`
  - gRPC 服務端（:50051），查詢 DB/Redis 並回傳 protobuf
  - HTTP 服務端（:8080）：`/api/token/powersync`、`/api/.well-known/jwks.json`、`/api/embed`、`/api/static-version`（本環境靜態資料版本，App 離線快取的 epoch，ADR-0017）
  - 串流以 Redis Pub/Sub 實作（`sub.Channel()` channel-based，無 busy-loop）
  - pgxpool：MaxConns=20，MinConns=2，MaxConnLifetime=30m，MaxConnIdleTime=5m
  - Redis pool：PoolSize=20，MinIdleConns=3，PoolTimeout=5s
  - process 內 TTL cache（`cache.go`）：`BusRouteStatic` / `BikeStatic` 各快取 1 小時
  - `Near_Station_Service`：5 種站型以 goroutine 並行查詢；共用單一 `*resty.Client`（MOTIS `/api/v1/one-to-many`）
  - 鐵路（台鐵 / 高鐵）為純讀取路徑：查已載入的環境 schema 表，miss 時回傳 `codes.NotFound`，不再向 TDX 抓取

## 外部依賴

| 依賴 | 說明 |
|---|---|
| PostgreSQL | 靜態資料、時刻表、站點、路線等持久化 |
| MySQL 封存主機 | 觀測歷史與上游原文；`bus_eta_history`／`bus_stop_event`／`bike_availability_history` 唯一的家，另有 `raw_tdx_archive` 與 `live_archive*`。`ARCHIVE_MYSQL_DSN`，僅 prod。見 `docs/archive.md`、ADR-0023 |
| TDX REST API | 排程擷取交通靜態與即時資料 |
| TDX MQTT | 推送式即時告警（`mqtt.transportdata.tw:8883`） |

## 資料流

```
# 靜態資料採兩階段
TDX REST API ──03:00 ingestor（TDX 憑證僅 prod，無憑證時零請求）──→ raw_tdx（共用 schema）
raw_tdx ──03:30（每個環境 loader，ROLE=loader）──→ PostgreSQL（該環境 PG_SCHEMA 靜態）──changetovector（同一 loader 進程接續）──→ search_vector 列（名稱 + 讀音 alias；見 ADR-0013）

TDX REST API ──即時排程──→ functions ──→ Redis（ETA 快取 + Pub/Sub）

TDX MQTT ──push──→ functions ──→ Redis（告警快取 + Pub/Sub）

Redis Pub/Sub ──→ router ──gRPC stream──→ Flutter App

# router 為純讀取路徑（含鐵路）：miss 時查 PostgreSQL，不再回抓 TDX
PostgreSQL ──→ PowerSync ──sync──→ Flutter SQLite（離線搜尋）

           └──→ router /api/token/powersync ──→ JWT
```

## 專案路徑

- `services/worker/*.go`：排程、原始落地（ingestor）、loader、MQTT 訂閱
- `services/api/*.go`：gRPC 服務、HTTP 端點
- `models/*.proto`：proto 定義
- `models/*_grpc.pb.go`：gRPC 介面
- `powersync/`：PowerSync 設定（`config.yaml`、`sync-rules.yaml`）
- `osrm-data/`：Geofabrik 的台灣 OSM extract（`motis-import` 唯讀掛載；目錄名沿用，改名沒有功能收益）
