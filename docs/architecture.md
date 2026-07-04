made by claude
# 架構說明

## 部署環境

單台 Ubuntu 主機（8 GB RAM），所有服務透過 Docker Compose 統一管理。

```
Flutter App
    │
    ├─ gRPC :50051      → router
    ├─ HTTP :8080       → router (JWT / JWKS / embed)
    └─ HTTP :8081       → PowerSync (資料同步)

router / functions / powersync / osrm / redis
    全部在同一台 Ubuntu 主機
    │
    └─ Azure PostgreSQL（外部）
```

## 服務一覽

| 服務 | 映像 | 對外端口 | 記憶體上限 |
|---|---|---|---|
| redis | redis:7-alpine | 127.0.0.1:6379 | 512 MB |
| router | bus-router (Go) | 50051, 8080 | 256 MB |
| functions | bus-functions (Go) | — | 192 MB |
| ingestor | bus-functions (Go, `ROLE=ingestor`；TDX 憑證僅 prod，其他環境為 no-op) | — | 256 MB |
| powersync | journeyapps/powersync-service | 8081 | 512 MB |
| osrm | osrm/osrm-backend | 127.0.0.1:5000 | 1536 MB |
| ollama | ollama/ollama (custom) | 127.0.0.1:11434 | 800 MB |

Redis 與 OSRM 僅對 localhost 開放，不對外暴露。

## 程式結構

- `services/functions`
  - 排程執行器；一個映像以 `ROLE` 環境變數分兩種模式：
    - `ROLE=ingestor`：Stage 1，03:00 把 TDX 原始 payload 落地共用 `raw_tdx` schema。容器每個環境都會啟動（只有 `make up-test` 不啟動），但 TDX 憑證只放在 prod；其他環境的 ingestor 沒有憑證，抓取不會發生。
    - `ROLE=""`（每個環境）：Stage 2 loader（03:30 `raw_tdx` → 該環境 `PG_SCHEMA`）＋ 即時 ETA ＋ MQTT ＋ 通知。
  - TDX MQTT 訂閱（`mqtt.go`），接收即時告警並推送至 Redis Pub/Sub
  - 使用 `robfig/cron` 設定排程（見 `docs/ingestion.md`）
  - pgxpool：MaxConns=10，MinConns=2，MaxConnLifetime=30m，MaxConnIdleTime=5m
  - Redis pool：PoolSize=20，MinIdleConns=3，PoolTimeout=5s
- `services/router`
  - gRPC 服務端（:50051），查詢 DB/Redis 並回傳 protobuf
  - HTTP 服務端（:8080）：`/api/token/powersync`、`/api/.well-known/jwks.json`、`/api/embed`
  - 串流以 Redis Pub/Sub 實作（`sub.Channel()` channel-based，無 busy-loop）
  - pgxpool：MaxConns=20，MinConns=2，MaxConnLifetime=30m，MaxConnIdleTime=5m
  - Redis pool：PoolSize=20，MinIdleConns=3，PoolTimeout=5s
  - process 內 TTL cache（`cache.go`）：`BusRouteStatic` / `BikeStatic` 各快取 1 小時
  - `Near_Station_Service`：5 種站型以 goroutine 並行查詢；共用單一 `*resty.Client`（OSRM）
  - 鐵路（台鐵 / 高鐵）為純讀取路徑：查已載入的環境 schema 表，miss 時回傳 `codes.NotFound`，不再向 TDX 抓取（ADR-0005）

## 外部依賴

| 依賴 | 說明 |
|---|---|
| Azure PostgreSQL | 靜態資料、時刻表、站點、路線等持久化 |
| TDX REST API | 排程擷取交通靜態與即時資料 |
| TDX MQTT | 推送式即時告警（`mqtt.transportdata.tw:8883`） |
| Ollama (本機) | 向量嵌入計算（`qwen3-embedding:0.6b`，Docker 內部服務） |

## 資料流

```
# 靜態資料採兩階段（ADR-0005）
TDX REST API ──03:00 ingestor（TDX 憑證僅 prod，其他環境為 no-op）──→ raw_tdx（共用 schema）
raw_tdx ──03:30（每個環境 functions）──→ PostgreSQL（該環境 PG_SCHEMA 靜態）

TDX REST API ──即時排程──→ functions ──→ Redis（ETA 快取 + Pub/Sub）

TDX MQTT ──push──→ functions ──→ Redis（告警快取 + Pub/Sub）

Redis Pub/Sub ──→ router ──gRPC stream──→ Flutter App

# router 為純讀取路徑（含鐵路）：miss 時查 PostgreSQL，不再回抓 TDX
PostgreSQL ──→ PowerSync ──sync──→ Flutter SQLite（離線搜尋）

Flutter App ──→ router /api/embed ──→ ollama:11434 ──→ 向量
           └──→ router /api/token/powersync ──→ JWT
```

## 專案路徑

- `services/functions/*.go`：排程、原始落地（ingestor）、loader、MQTT 訂閱
- `services/router/*.go`：gRPC 服務、HTTP 端點
- `models/*.proto`：proto 定義
- `models/*_grpc.pb.go`：gRPC 介面（已提交）
- `powersync/`：PowerSync 設定（`config.yaml`、`sync-rules.yaml`）
- `osrm-data/`：OSRM 預處理檔案（gitignored，手動放置）
