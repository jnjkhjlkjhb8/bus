made by claude
# SLO（Service Level Objectives）

使用者可感知的 SLI/SLO 定義：每項有 測量來源（對應到 code 內的 metrics/log 欄位）與初始目標值。**這是 repo 端
交付**——實際告警規則、dashboard、on-call rotation 是 operator 動作，不在
本文件範圍（見 `docs/runbooks/incident-response.md`）。

**初始值待量測校正**：以下目標值是合理保守的起點，不是量測後的承諾。
比多數 SLO 文件假設的基礎設施更緊；目標值第一次修訂前，先累積至少兩週的
真實量測（`GET /metrics`、functions 的結構化 log）
再決定要收緊還是放寬。

## 1. API availability

- **定義**：router gRPC/HTTP 請求成功完成（非 5xx / `codes.Internal` /
  `codes.Unavailable`）的比例。
- **測量來源**：`GET /metrics` 的 `router_grpc_requests_total` /
  `router_grpc_errors_total`（按 method 標籤，見
  `services/obs/sentry.go` 的 `UnaryInterceptor`/`StreamInterceptor` —
  任何非 nil 的 gRPC 回傳錯誤都計入，包含 `codes.NotFound`，因為這是
  API 層級「這次呼叫沒有成功回傳資料」的度量）與
  `router_http_requests_total` / `router_http_errors_total`（按 route
  pattern 標籤，只有 5xx 才計入 error，見 `safeAccessLogger`）。
  `router_db_errors_total`（第 8 節之外的另一個計數器，見
  `services/router/main.go` 的 `grpcStatusFor`）才是排除
  `codes.NotFound` 的版本——那是專門量測「後端儲存本身壞掉」而非
  「這次 API 呼叫沒中」的訊號，兩者刻意分開。
- **初始目標**：99.5% 月可用率（≈ 每月 3.6 小時的錯誤預算）。單機部署、
  無多活備援，這個數字反映「單一主機加計畫性維護」的現實，不是四個 9 的
  高可用承諾。

## 2. API latency

- **定義**：一元 RPC / HTTP 請求的 P95 延遲。
- **測量來源**：目前沒有延遲直方圖（P2-04 範圍內只加計數器，不引入
  histogram/summary，避免無 Prometheus client library 情況下手刻分位數
  估計器的複雜度）；`services/router/http.go` 的 `safeAccessLogger` 已把
  每筆請求的 `latency=` 寫進 stdout 結構化 log，可先用日誌聚合抓 P95。
- **初始目標**：P95 < 500ms（本地 PostgreSQL 查詢 + Redis 快取路徑）；
  MaaS 路線規劃（呼叫 TDX + OSRM）例外，P95 < 3s。
- **待辦**：若日誌聚合估計顯示目標明顯不合理，再評估是否值得為
  histogram 引入 Prometheus client library（目前 `router_grpc_*` /
  `router_http_*` 沿用 repo 既有的手刻 plain-text exposition，見
  `services/obs/metrics.go`）。

## 3. Live ETA freshness

- **定義**：從 TDX 產生資料到使用者透過 gRPC live stream 收到更新的延遲；
  近似值用「排程 cron cadence + 該次 tick 是否 overrun」估計，而非端到端
  時戳（TDX 沒有提供資料產生時戳可比對）。
- **測量來源**：
  - 公車/公共自行車：`@every 30s`；MRT `@every 10s`；
    TRA `@every 2min`。每次 tick 的成功/失敗與 overrun 都寫
    `services/functions/live.go` 的 `[LIVE] action=tick ...` 結構化 log。
- **初始目標**：同一 job 連續 3 次 tick 失敗（約 30s cadence 下 1.5 分鐘）
  即視為新鮮度劣化，觸發 `docs/runbooks/incident-response.md` 的檢查流程。

## 4. Stream continuity

- **定義**：gRPC live stream 非預期斷線率（排除客戶端主動取消：
  `context.Canceled`）。
- **測量來源**：`GET /metrics` 的 `router_stream_disconnects_total`（見
  `services/router/livestream.go` 的 `streamLive`；目前是單一未分標籤的
  計數器，涵蓋所有終止原因——client 斷線、upstream 關閉、send 失敗——按
  channel 標籤化會重新引入使用者可控 ID 的高基數問題，見
  `services/obs/metrics.go` 的說明）；搭配
  `router_live_evicted_subscribers_total`（既有的 `liveHub` 統計，慢客戶端
  被踢除次數）判斷斷線是否源自伺服器端佇列滿載。
- **初始目標**：`router_live_evicted_subscribers_total` 的成長率應遠低於
  `router_stream_disconnects_total`（多數斷線應是正常的客戶端生命週期，不
  是伺服器端過載造成的強制踢除）；沒有量測基準前不設絕對比例門檻。

## 5. PowerSync sync lag

- **定義**：PostgreSQL 寫入到 PowerSync SQLite 複本可查詢之間的延遲。
- **測量來源**：目前沒有 repo 端量測（PowerSync 是 journeyapps 託管服務，
  `docker/docker-compose.yaml` 的 `powersync` service；其自身的健康與同步
  延遲指標屬於該服務的營運面，不在這次 O8 範圍內新增）。PowerSync 官方
  admin API/dashboard 是量測來源；operator 待辦。
- **初始目標**：待 operator 從 PowerSync 自身監控填入；repo 端只能保證
  PowerSync 讀到的來源資料庫沒有落後（見 loader 的 pipeline marker lag，
  第 8 節）。

## 6. Search success

- **定義**：`GET /api/search` 回傳非 5xx 且非空結果集的比例（空結果集是
  合理的「查無資料」，不是失敗；5xx 才是失敗）。
- **測量來源**：`router_http_requests_total{path="/api/search"}` /
  `router_http_errors_total{path="/api/search"}`（同第 1 節機制，見
  `services/router/search.go` 的 `handleSearch`，所有查詢/embedding 失敗
  都回 500，因此已完整落在 http error 計數內）。
- **初始目標**：5xx 錯誤率 < 1%。

## 7. Notification delivery

- **定義**：抵達／到站提醒從觸發條件成立到 FCM 送出成功的比例。
- **測量來源**：`firebase_arrival_reminder`（DB 表，`status` 欄位
  `CHECK (status IN ('pending','sending','cancelled','fired','expired'))`，
  見 `migrations/005_firebase_notifications.sql`）。commit `03e4a2c94`
  「fix: reclaim arrival reminders stuck in sending after a crash」讓卡在
  `sending` 的提醒在 claim 逾時（`ReminderClaimTimeout`，
  `services/functions/notify/notification_store.go`）後被下次 tick 回收
  重試，而不是永久卡住。目前沒有彙總成功率的 log gauge 或 metrics
  endpoint——這是已知缺口，留給下一輪迭代；現況只能靠查
  `firebase_arrival_reminder` 的 `status` 分布（例如 `fired` 對
  `pending+sending` 的比例）。
- **初始目標**：待 operator/下一輪迭代補上彙總查詢後再訂目標值。

## 8. Pipeline freshness（loader / changetovector / marker lag）

- **定義**：nightly ingest → load → changetovector → computeTravelAvg 這條
  管線多久內對下游可用。
- **測量來源**：
  - Pipeline marker lag：`services/functions/pipeline_marker.go` 的
    `[PIPELINE] action=record_marker event=recorded ... gauge=marker_lag_seconds`
    結構化 log（`load` 與 `changetovector` 兩個 job 都會寫）。
  - Quarantine ratio：`services/functions/loader.go` 的
    `[LOAD] action=quarantine event=dropped ... ratio=` 結構化 log
    （per dataset/partition，`loadQuarantine.report`）。
- **初始目標**：`load` 與 `changetovector` 的 `marker_lag_seconds` 應在各自
  排程 cron 的下一個 stage 開始輪詢前完成（`load` 03:30 起算，
  `changetovector` 03:45 起算，`waitForPipelineMarker` 的
  `pipelineMarkerPollDeadline` 目前是 2 小時，即隱含的軟性上限）；超過
  1 小時視為劣化訊號。

## 9. Mobile startup success

- **定義**：App 冷啟動到首頁可互動（不含 PowerSync/Firebase 完成，見
  `docs/requirements.md` 的「首屏不能等待」約束）的成功率／耗時。
- **測量來源**：目前沒有 repo 端量測（無 client 端 crash-free 或
  startup-time 遙測管線）。`app/integration_test/metro_open_perf_test.dart`
  只是本機效能迴歸測試，不是生產遙測。
- **初始目標**：待補 client 端遙測後再訂目標值；本次 O8 範圍不新增
  client SDK 依賴（AGENTS.md「不引入新第三方依賴」）。

## 測量來源總覽

| 訊號 | 來源 | 檔案 |
|---|---|---|
| gRPC/HTTP 請求與錯誤計數 | `GET /metrics`（router，需 `ROUTER_METRICS_TOKEN`） | `services/obs/metrics.go`, `services/router/http.go` |
| Live stream 斷線/踢除計數 | `GET /metrics` | `services/router/livestream.go`, `services/router/live_hub.go` |
| Redis/DB error 計數 | `GET /metrics` | `services/obs/metrics.go` |
| Overrun/skip | 結構化 log（`event=overrun`, cron 內建 skip） | `services/functions/live.go`, `services/functions/main.go` |
| Pipeline marker lag | 結構化 log（`gauge=marker_lag_seconds`） | `services/functions/pipeline_marker.go` |
| Quarantine ratio | 結構化 log（`event=dropped ... ratio=`） | `services/functions/loader.go` |
| Container liveness | health touch-file + compose healthcheck | `services/functions/healthfile.go`, `docker/docker-compose.yaml` |

**為何 functions 用檔案而非 HTTP endpoint**：functions 的三種角色
（legacy prod / ingestor / loader）都沒有 HTTP listener（`main.go` 的
`switch mode` 只啟動 cron scheduler，不開任何 port）。新開網路 port 會在
單機部署上新增一塊沒有對應防護（TLS、rate limit、credential）的攻擊面，
換來的操作收益很小——`healthFilePath`（`services/functions/healthfile.go`）
用「寫本地 tmpfs 檔案給 compose healthcheck 讀」這個模式在本專案夠用。
若未來需要 Prometheus 直接 scrape functions（例如接上外部 dashboard），
再評估另開唯讀、僅限 backend network 的 `/metrics` port——那會是新的
ADR，不在本次 O8 範圍內。
