made by claude
# 資料擷取與排程

靜態資料採兩階段流程（ADR-0005）：**Stage 1** 由 `ROLE=ingestor` 容器把 TDX 原始 payload 落地到共用的 `raw_tdx` schema——ingestor 容器每個環境都會啟動，但 TDX 憑證只放在 prod，其他環境沒有憑證時 ingestor 直接跳過、不會發出任何請求（真正的 no-op）；**Stage 2** 由每個環境的 `functions` 容器把 `raw_tdx` 轉換寫入各自的 `PG_SCHEMA`。即時（realtime）排程不受此拆分影響，仍在 `functions`（`ROLE=""`）中執行。

## 排程時間

| 時間 | 角色 | 工作 |
|---|---|---|
| 每日 03:00 | ingestor（每環境都啟動；TDX 憑證僅 prod，無憑證時直接跳過、零請求）| `ingestRaw`：抓取所有靜態 TDX 端點，落地 `raw_tdx` |
| 每日 03:30 | functions（每個環境）| `load`：`raw_tdx` → 該環境 `PG_SCHEMA` |
| 每日 03:45 | functions | `changetovector`：向量更新（在 load 之後執行） |
| 每日 04:00 | functions | `computeTravelAvg`：公車旅行時間統計 |
| 每日 04:30 | functions | `cleanupBusHistory`：刪除 30 天前的 ETA 歷史 |
| 每 10 分鐘 | functions | `weatherSync`：CWA 天氣資料同步 |
| 每 2 分鐘 | functions | `traEta` |
| 每 30 秒 | functions | `bikeEta`, `busEta`（含通知派送） |
| 每 10 秒 | functions | `mrtEta` |

> 註：`busEta` 每 30 秒與 `bikeEta` 同一個排程觸發；`busDailyroute`（見下）在 `functions` 啟動時載入一次。

## Stage 1 — 原始落地（ingestor，每日 03:00）

`ROLE=ingestor` 容器每個環境都會啟動（base compose 定義它；只有 `make up-test` 不啟動），但 **TDX 憑證（`TDX_CLIENT_ID` / `TDX_CLIENT_SECRET`）只放在 prod**。`ingestRaw` 進入時先檢查憑證：**任一憑證為空時直接跳過整趟落地，不會發出任何請求**，只輸出一行 `[INGEST] action=raw event=idle reason=no_credentials`（cron 仍註冊，但是真正的 no-op）。有憑證時才逐一抓取每個靜態端點，把 TDX 回應原文（不解析）寫入 `raw_tdx.<table>`。落地寫入發生在 `callApi` 內：只有在成功 dump 之後才更新 Last-Modified / If-Modified-Since cache，避免某次 dump 失敗被後續 304 遮蔽而讓 `raw_tdx` 永久卡在舊資料。

> ⚠️ **共用 `raw_tdx` 的單一寫入者不變式**：staging 與 prod 共用同一個 Azure 資料庫，`raw_tdx` 之所以只有一個寫入者，**完全是因為 staging 的 TDX 憑證為空**。切勿在 staging（或任何共用 prod 資料庫的環境）設定 TDX 憑證——兩個 ingestor 會在共用的 `raw_tdx` 上互相競爭彼此的分割 `DELETE`/`INSERT`，造成資料損毀。若 staging 必須自行落地，請改用獨立的資料庫。

分割替換（partition-replace）策略：

- 有分割欄（`city` / `system` / `traindate`）的表：只 `DELETE` 該分割再插入，其餘分割不動。
- 無分割欄的表：整表 `TRUNCATE` 後重寫。

### 落地的資料集

| 類別 | TDX 端點 | `raw_tdx` 表 | 分割欄 |
|---|---|---|---|
| 公車（9 支 API × 23 城市）| `/v2/Bus/{Route,StopOfRoute,Shape,Schedule,Station,StationGroup,Operator,RouteFare,DailyTimeTable}/City/{City}`（InterCity 用 `/InterCity`）| `bus_route`, `bus_stopofroute`, `bus_shape`, `bus_schedule`, `bus_station`, `bus_stationgroup`, `bus_operator`, `bus_routefare`, `bus_dailytimetable` | `city` |
| 自行車 | `/v2/Bike/Station/City/{City}`（跳過無 feed 的縣市）| `bike_station` | `city` |
| 捷運（Metro）| `/v2/Rail/Metro/{Station,FirstLastTimetable,ODFare}/{System}` | `metro_station`, `metro_schedule`, `metro_odfare` | `system` |
| 台鐵 / 高鐵 靜態 | `/v2/Rail/{TRA,THSR}/Station`、`/v2/Rail/{TRA,THSR}/ODFare` | `tra_station`, `thsr_station`, `tra_odfare`, `thsr_odfare` | 無 |
| 台鐵時刻表 | `/v2/Rail/TRA/DailyTimetable/TrainDate/{date}`（今日 +0..+60）| `tra_dailytimetable` | `traindate` |
| 高鐵時刻表 | `/v2/Rail/THSR/DailyTimetable/TrainDate/{date}`（今日 +0..+45）| `thsr_dailytimetable` | `traindate` |

Metro 系統碼各端點不同（不是每個系統都發佈每種 feed）：

- Station：`TRTC`, `KRTC`, `KLRT`, `TYMC`, `NTMC`（5 個）
- FirstLastTimetable：`TRTC`, `KRTC`, `KLRT`, `TYMC`（4 個）
- ODFare：`TRTC`, `KRTC`, `KLRT`（3 個）

時刻表以「每個日期一個 `traindate` 分割」方式落地（今日為 day 0），因此 Stage 2 loader 的取用視窗（台鐵 today..+60、高鐵 today..+45）每個日期都有對應分割；某日期中途重抓只替換該日期分割，不會 TRUNCATE 整表。

> 白名單保留但目前未使用：`tra_traintype` 與 `bus_stop` 都不再（或從未）被 ingestor 抓取——`tra_traintype` 沒有 loader 轉換 spec，且 train-type 資料本就內含於每日時刻表 payload；`bus_stop` 的 `Stop` 端點不在 `ingestBusAPIs`，`bus_stop` 也已從 `rawDumpTarget` 的 `busTables` 對照移除。兩者的白名單條目與 DDL 仍保留（Azure 上可能已建表，移除不值得），程式碼中以註解標明其為未使用。

## Stage 2 — 載入（loader，每個環境，每日 03:30）

每個環境的 `functions` 容器在 03:30 執行 `runLoad`（`registerLoaderCrons`），把 `raw_tdx` 轉換寫入自己的 `PG_SCHEMA`。**loader 從不呼叫 TDX**。

- **協調機制**：固定的 03:00 / 03:30 時間差，加上每個分割的 `fetched_at` 新鮮度檢查。若某分割最新的 `fetched_at` 早於 27 小時（`staleAfter`），loader 跳過該分割並輸出 `[LOAD] action=skip event=stale`，保留環境 schema 內既有的好資料，而不是用「其實沒發生的落地」覆寫。已接受的城市內 torn-read 風險：若落地超過 30 分鐘時間差，`loadBus` 可能讀到某城市今天的 `bus_route` 卻搭配昨天的 `bus_stopofroute`（各表各自為內部一致的快照，結果是降級而非損毀）；我們刻意不加逐階段新鮮度檢查——時間差固定、`bus_route` 已有 27h 閘門，且此情況罕見並在下次成功落地時自我修復。
- **重建 payload**：`rawTDXSource.datasetJSON` 以 `to_jsonb` 重建每列的小寫 key JSON 陣列（去掉 `fetched_at` 與分割欄等 loader 記帳欄位），schema-qualified 讀取 `raw_tdx.<table>`，因此不受 sink pool 的 `search_path=PG_SCHEMA` 影響。重建出的 bytes 包成 `*json.Decoder` 餵給既有的轉換函式（轉換 SQL 與拆分前的 legacy 版本 byte-identical，ADR-0005：transforms 重用不重寫）。
- **環境路由**：`shared.ConnectDB` 把 sink pool 的 `search_path` 釘在 `PG_SCHEMA`，因此 loader 未加 schema 前綴的 upsert 落在該環境 schema；`raw_tdx.*` 讀取則永遠 schema-qualified。
- **獨立的 raw 讀取 DSN**：`RAW_DATABASE_URL` 若設定，loader 會另開一個 pool 讀共用的 Azure `raw_tdx`（唯讀），同時把轉換結果 sink 到自己的本地 schema（`db`）；未設定時退回用 `db`（單一 cluster 部署零行為改變）。
- **啟動回填**：`LOAD_ON_BOOT=true` 時，容器啟動即先跑一次 03:30 load，讓新部署不必等到隔天 tick 就先回填自己的 schema（對應 ingestor 的 `INGEST_ON_BOOT`）。

### loader registry（載入順序）

`loaderRegistry` 是 loader 認得的資料集清單，依序載入。順序不變量：`bus_operator` 必須排在 `bus` 之前（`loadBus` 會回讀 `bus_operators`）。

| key | `raw_tdx` 來源表 | 分割 | 目的（環境 schema / Redis）|
|---|---|---|---|
| `bus_operator` | `bus_operator` | 23 城市 | `bus_operators` |
| `bus` | `bus_route`（關聯多個 bus 表）| 23 城市 | `bus_subroutes`, `bus_stations`, `bus_schedule`, `bus_static` … |
| `bus_dailytimetable` | `bus_dailytimetable` | 城市（跳過無 feed）| **Redis** `bus_daily_timetable:{sub_route_uid}` |
| `bike` | `bike_station` | 城市（跳過無 feed）| `bike_stations` |
| `mrt_station` | `metro_station` | system | `mrt_station` |
| `mrt_firstlast` | `metro_schedule` | system | `mrt_schedule` |
| `mrt_odfare` | `metro_odfare` | system | 捷運 OD 票價矩陣 |
| `tra_station` | `tra_station` | 無 | `tra_stations` |
| `thsr_station` | `thsr_station` | 無 | `thsr_stations` |
| `tra_fare` | `tra_odfare` | 無 | `tra_fares` |
| `thsr_fare` | `thsr_odfare` | 無 | `thsr_fares` |
| `tra_timetable` | `tra_dailytimetable` | traindate（today..+60）| `tra_timetable` |
| `thsr_timetable` | `thsr_dailytimetable` | traindate（today..+45）| `thsr_timetable` |

> `bus_dailytimetable` 是唯一寫入 **Redis** 而非環境 schema 靜態表的 load spec（`loadBusDailyTimetable`）。`tra_traintype` 已落地但沒有對應 load spec；`bus_stop` 為白名單目標但未被抓取（見 Stage 1 註）。

## Fixture 匯出與 replay

loader 測試以 `raw_tdx` fixture 做確定性 replay，不需網路：

```bash
DATABASE_URL=... go run ./scripts/export-fixtures \
  -table thsr_station -out services/functions/testdata/raw_tdx/thsr_station.json
DATABASE_URL=... go run ./scripts/export-fixtures \
  -table tra_dailytimetable -partcol traindate -part 2026-07-05 -out <file>
```

`export-fixtures` 是唯讀工具，重建查詢與 `rawTDXSource.datasetJSON` 同形。測試中的檔案 `loadSource` adapter（`fixtureSource`，`loader_test.go`）從 `services/functions/testdata/raw_tdx/` 讀取已提交的 fixture，因為匯出與重建契約一致（小寫 key、無 `fetched_at`），fixture 可 byte-identical 地穿過 loader 的真實轉換函式。

## busDailyroute（啟動時載入）

`busDailyroute` 在 `functions` 啟動時執行一次，把公車每日時刻表載入 Redis：

- 寫入 Redis：`bus_daily_timetable:{sub_route_uid}`（TTL 23 小時 30 分）

（03:30 loader 的 `bus_dailytimetable` spec 走同一個 `loadBusDailyTimetable`，寫同一組 Redis key 與 TTL，資料來源改為 `raw_tdx`。）

## bikeEta

- 來源 API
  - `/v2/Bike/Availability/City/{City}`
- 寫入 Redis
  - `bike_availability:{station_uid}`（TTL 2 分鐘）

## mrtEta

- 來源 API
  - `/v2/Rail/Metro/LiveBoard/{System}`
- 寫入 Redis
  - `mrt_live:{system}:{station_id}:{line_id}`（TTL 2 分鐘）
  - Pub/Sub 頻道：`mrt_live:{system}:{station_id}`

## traEta

- 來源 API
  - `/v2/Rail/TRA/LiveTrainDelay`
  - `/v2/Rail/TRA/LiveBoard`
- 寫入 Redis
  - `tra:delay`（hash，3 分鐘 expire）
  - `tra:delay:all`（TTL 3 分鐘，同名頻道發 Pub/Sub）
  - `tra:liveboard:{station_id}`

## 鐵路時刻表查詢（router 讀取路徑）

台鐵 / 高鐵時刻表、站點、票價現在完全由 loader 從 `raw_tdx` 寫入環境 schema，**router 不再持有時刻表的 TDX client**（ADR-0005）。router 對這些查詢是純讀取路徑：cache miss 時查環境 schema 的已載入表；若查無資料（例如日期超出已落地視窗 today..+60 / +45），回傳 `codes.NotFound` 而不觸發 TDX 抓取。

（`services/router/tra.go` / `thsr.go` 中仍有 `callApi` / `getToken`，那是 MaaS 路線規劃器用的，不在鐵路靜態時刻表讀取路徑上。）

## busEta（每 30 秒）

各城市以 bounded worker pool（concurrency=4）並行處理。每個城市的 `busstaticmp`（路線站點 map）在首次需要時查 DB 並快取於 process 內，`dailyRoute` 完成後清除快取。

除寫入 Redis 外，每次執行還會：

1. **收集 ETA 歷史**（`stop_status == 0` 的站點）
   - 使用 `pgx.CopyFrom` 批次寫入 `bus_eta_history`
   - 包含天氣快照（從 Redis `weather:{city}` 讀取）、最近公車距離（haversine）、假日旗標

2. **填補 NextBusTime 預測**（`stop_status == 1` 且 `NextBusTime == ""`）
   - 每城市執行前批次查詢：`batchNextDepartures`（`bus_schedule`）和 `batchTravelAvg`（`bus_travel_avg`），不做 per-stop DB 呼叫
   - 旅行時間無資料時以 `stop_sequence_ratio × max` 估算
   - 若模型已載入，加上 XGBoost delay 修正值
   - 結果以 RFC3339 格式填入 proto，由 router 直接傳出

## weatherSync（每 10 分鐘）

同時呼叫兩支 CWA Open Data API，需設定 `CWA_API_KEY`：

| API | 資料集 | 內容 |
|---|---|---|
| `O-A0003-001` | 自動氣象站觀測 | 溫度、風速、濕度（各縣市最新一筆觀測站） |
| `F-B0046-001` | 降水量網格預報 | 降水量（0.0125° 網格，以城市中心座標查格點） |

合併後寫入 Redis `weather:{city}`（15 分鐘 TTL）。

## computeTravelAvg（每日 04:00）

從 `bus_eta_history` 近 7 天的資料偵測 estimate 由正轉負的「抵達事件」，結合 `bus_schedule` 的出發時間，計算各站旅行時間中位數，寫入 `bus_travel_avg`。僅採計 ≥ 10 筆樣本的資料；GTFS 冷啟動種子（`sample_count = 0`）會被觀測資料覆蓋。

## cleanupBusHistory（每日 04:30）

刪除 `bus_eta_history` 中 30 天前的資料（`recorded_at < NOW() - INTERVAL '30 days'`）。

## GTFS 冷啟動（手動執行）

```bash
DATABASE_URL=... python3 scripts/gtfs_seed.py
```

從 `temp/gtfs/` 讀取 GTFS 靜態資料，計算各站旅行時間中位數，寫入 `bus_travel_avg`（`sample_count = 0`）。在觀測資料累積前提供 fallback 預測。

## TDX MQTT 訂閱

- 實作位置：`services/functions/mqtt.go`，啟動函數 `startMQTT(rc)`
- 在 `main.go` 於 cron 排程啟動後呼叫，程式結束時呼叫 `Disconnect(500)`
- 若 `MQTT_CLIENT_ID` / `MQTT_USERNAME` / `MQTT_PASSWORD` 任一為空則跳過，不影響其他排程

### 連線
- Broker：`mqtts://mqtt.transportdata.tw:8883`（MQTTS / TLS）
- 憑證：`MQTT_CLIENT_ID`、`MQTT_USERNAME`、`MQTT_PASSWORD`
- `SetAutoReconnect(true)` + `SetConnectRetry(true)` + 每 10 秒重連
- 所有訂閱於 `OnConnectHandler` 中重新建立（確保斷線重連後恢復）

### 訂閱主題與 Redis 行為

| MQTT topic（QoS 1）| Redis key | TTL |
|---|---|---|
| `v2/Bus/RealTimeNearStop/City/#` | `mqtt:v2:Bus:RealTimeNearStop:City:{city}:{routeId}` | 60 秒 |
| `v2/Bus/News/City/+` | `mqtt:v2:Bus:News:City:{city}` | 5 分鐘 |
| `v2/Bus/News/InterCity` | `mqtt:v2:Bus:News:InterCity` | 5 分鐘 |
| `v2/Rail/Metro/Alert/#` | `mqtt:v2:Rail:Metro:Alert:{system}` | 5 分鐘 |
| `v3/Rail/TRA/Alert` | `mqtt:v3:Rail:TRA:Alert` | 5 分鐘 |
| `v2/Rail/THSR/AlertInfo` | `mqtt:v2:Rail:THSR:AlertInfo` | 5 分鐘 |

- Redis key 推導規則：`"mqtt:" + topic.replace("/", ":")`
- 每筆訊息：`rc.Set(key, payload, ttl)` 存快取 + `rc.Publish(key, payload)` 推送至 Pub/Sub
- 訊息格式：TDX 標準 JSON，**不解析**，原文儲存

## 向量更新 (changetovector，每日 03:45)

在 03:30 load 之後執行（因此讀到的是 loader 剛寫好的表，而非已退役的 03:00 直抓寫入）。

- 來源（`vector.go` 的六張表）
  - `bus_subroutes`, `bus_station_groups`, `bike_stations`, `mrt_station`, `tra_stations`, `thsr_stations`
- 目的表
  - `search_vector`
- 向量模型
  - `qwen3-embedding:0.6b`（Ollama 本機服務，`http://ollama:11434/api/embed`）
  - 維度：1024，pgvector `vector(1024)` 欄位，HNSW 索引
