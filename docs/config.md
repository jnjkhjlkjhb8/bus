made by claude
# 設定與環境變數

## Redis
- `REDIS_ADDR`
  - 格式：`host:port`

## PostgreSQL
- `DATABASE_URL`
  - 連線字串

## TDX
- `TDX_CLIENT_ID`
- `TDX_CLIENT_SECRET`
  - ingestor 容器（`ROLE=ingestor`）每個環境都會啟動（只有 `make up-test` 不啟動），但 TDX 憑證只放在 prod；缺任一憑證時 `ingestRaw` 直接跳過整趟落地、不發出任何請求（真正的 no-op）。
  - staging / test 留空即可（ADR-0005 Consequences）：loader 從 `raw_tdx` 載入，不呼叫 TDX。
  - ⚠️ staging 與 prod 共用同一個 Azure 資料庫，切勿在 staging 設定 TDX 憑證：兩個 ingestor 會在共用的 `raw_tdx` 上競爭彼此的分割 `DELETE`/`INSERT`。若 staging 必須落地，請改用獨立資料庫。

## 資料載入（loader）
- `LOAD_ON_BOOT`
  - functions 容器啟動時立即執行一次 03:30 load（回填該環境 schema）。
  - 預設關閉；設為 `"true"` 啟用。對應 ingestor 的 `INGEST_ON_BOOT`。
- `INGEST_ON_BOOT`
  - `ROLE=ingestor` 啟動時立即執行一次 03:00 raw landing。
  - 預設關閉；設為 `"true"` 啟用。
- `RAW_DATABASE_URL`（選用）
  - loader 讀取共用 `raw_tdx` 的 DSN；未設定時退回 `DATABASE_URL`。
  - 用於 test / staging 讀共用 Azure `raw_tdx`（唯讀），同時 sink 到自己的本地 schema。

## TDX MQTT
- `MQTT_CLIENT_ID`
  - 由 TDX 會員中心 → 資料服務 → 存取金鑰取得
  - 若留空則略過 MQTT 訂閱
- `MQTT_USERNAME`
- `MQTT_PASSWORD`

## HTTP / PowerSync
- `POWERSYNC_URL`
  - Flutter build-time dart-define: `--dart-define=POWERSYNC_URL=http://your-debian-server:8080`
  - PowerSync service endpoint (Debian server)
- `API_BASE_URL`
  - Flutter build-time dart-define: `--dart-define=API_BASE_URL=http://your-go-server:8080`
  - Go backend HTTP server (JWT + embed endpoints)
  - Default: `http://localhost:8080`

## PowerSync server (powersync/.env)
- `DATABASE_URL`
  - Azure PostgreSQL connection string (same as Go backend)
- `POWERSYNC_JWKS_URL`
  - Full URL of Go backend JWKS endpoint, reachable from Debian server
  - e.g. `http://go-server-host:8080/api/.well-known/jwks.json`

## Bus ETA Prediction

- `CWA_API_KEY`
  - CWA Open Data API 金鑰，申請網址：opendata.cwa.gov.tw
  - 若留空則略過天氣同步（weatherSync 不執行）
- `BUS_ETA_MODEL_PATH`
  - XGBoost 模型檔案路徑
  - 預設：`./model/bus_eta.json`
  - 若檔案不存在則僅用班表 + travel avg（無 ML 修正）
