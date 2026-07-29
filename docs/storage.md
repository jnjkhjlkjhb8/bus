made by claude
# 儲存層與資料表

## 主要資料表

### bus
- `bus_subroutes`
  - 子路線與站點、班表整理後資料（含 `Direction.first_bus_time`/`last_bus_time`/`holiday_*`）
- `bus_static`
  - 序列化後的 protobuf bytes
- `bus_stations`
  - 公車站點資訊與座標
- `bus_station_stop_map`
  - 站點與路線對應（每次 `loadBus` 前先刪除舊資料再重新插入，避免殘留已刪路線的停靠點）
- `bus_schedule`
  - 班表與發車頻率；分割替換（partition-replace）：`saveschedule` 在單一交易內先 `DELETE FROM bus_schedule WHERE sub_route_uid LIKE citymap[city] || '%'`，再從 `raw_tdx.bus_schedule` 展開後純 `INSERT`（無 DISTINCT ON、無 ON CONFLICT）；`updated_at` 蓋 NOW()。無自然鍵唯一約束——環狀路線同一趟重複經過同站會產生相同自然鍵，這些列刻意全部保留

### bike
- `bike_stations`
  - 站點、容量、地址、座標

### mrt
- `mrt_station`
  - 捷運站點與座標
- `mrt_schedule`
  - 捷運首末班車時間；分割替換（partition-replace）：`loadMrtFirstlast` 在單一交易內先 `DELETE FROM mrt_schedule WHERE system=$1`，再純 `INSERT` 全部列（無 DISTINCT ON、無 ON CONFLICT）；`updated_at` 蓋 NOW()（新鮮度探測 `MAX(updated_at) WHERE system=$1`）。無自然鍵唯一約束；serviceday bitmask 第 8 bit = NationalHolidays
- `mrt_adjacency`（ADR-0015；migration `2026-07-23-mrt-adjacency.sql`）
  - 捷運「同線相鄰站」邊集，捷運下車提醒 session 走的路網。欄位：`system, line_id, from_station_id, to_station_id, updated_at`；PK `(system, from_station_id, to_station_id)`。由 `loadMrtAdjacency`（loader）從已落地的 `raw_tdx.metro_s2straveltime`（TRTC）的 `TravelTimes` 段建立，**只取段、不取 `LineTransfer`**（一班車不跨轉乘邊）。每段的兩個方向都寫入，故 router 的 board→terminal BFS 以有向查表達成無向走訪。以 `ON CONFLICT` upsert 原地更新；來源短暫為空時 no-op，不刪好邊。

### rail
- `tra_stations`
- `thsr_stations`
- `tra_fares`
- `thsr_fares`
- `tra_timetable`
- `thsr_timetable`

### 到站/下車提醒（`firebase_arrival_reminder`，migration `005_firebase_notifications.sql`）
公車以 live ETA、鐵路以排程（`fire_at = 抵達 − lead`）觸發。捷運下車提醒（`route_type='mrt'`，ADR-0015）重用同一張表，欄位對應如下：
- `plate` = carID（車廂綁定）
- `route_key` = TripId（GetTrainInfo 回傳，等同擁擠度 feed 的 TrainNumber）
- `stop_key` = 目標站（下車站）ID
- `direction` = 該班車終點站（terminal）ID
- `lead_minutes` = **提前站數**（沿用該欄；stops-based lead，仍受 `CHECK (lead_minutes BETWEEN 1 AND 120)` 限制）
- `fire_at` = NULL（如公車，不排程；由 functions tracker 依即時位置觸發）
- `status` = `pending`（active）；lead 觸發時走既有 claim→sending→fired 機制。抵達/脫離/逾時等結束只更新 Redis session 狀態；**未曾 fire 的列**才由 tracker 標記 `expired`（已 fired 的列因 `CHECK (fired_at IS NULL OR status='fired')` 不可改，改由 `expires_at` 自然過期）

### 使用者回報（`feedback_thread` / `feedback_message`，migration `2026-07-27-feedback.sql`）
一則回報是一個 thread 加上它的第一則 message。拆成兩張表是因為 ops 的回覆就是同一個 thread 上的下一則 message——之後才長成這個形狀，等於要在資料庫上搬動線上資料，不如一開始就在旁邊多開一張表。
- `feedback_thread(id, install_id, category, diagnostics jsonb, status, created_at)`
  - `install_id` 與 `firebase_device` 是同一組匿名識別，但**刻意不設 FK**：關掉推播、或裝置列被清掉的使用者，仍然必須能回報問題
  - `category` 的 CHECK 與 Go 端的白名單重複，是為了讓未來的 client 版本無法悄悄擴張 ops 端的分類
  - `status` 只有 `open` / `closed`：讀回報走 SQL，沒有這欄的話待辦清單只會無限成長
  - 索引：`(install_id, created_at DESC)` 服務每日配額計數；`(created_at DESC) WHERE status='open'` 是 partial index，大小維持在待辦量而非全部歷史
- `feedback_message(id, thread_id, author, body, created_at)`
  - `author` 是 `user` / `ops` 的文字而非 boolean，因為 `ops` 那些列是人在 psql 裡手寫的
- **已讀狀態不進資料庫**：哪些回覆看過了存在 App 端 Hive，伺服器因此少一張表與一條 RPC

### bus ETA prediction
- `bus_eta_history`
  - 每 30 秒 `BusEta` 寫入，僅限 `stop_status == 0`（有 GPS 資料、正在行駛）
  - 欄位：sub_route_uid, stop_uid, direction, stop_sequence, total_stops, estimate, next_bus_time, src_update_time, city, hour, day_of_week, is_holiday, temperature, precipitation, wind_speed, humidity, plate_numb, bus_speed, bus_distance_m
  - 索引：`(sub_route_uid, stop_uid, direction, recorded_at DESC)`
  - 保留 30 天，每日 04:30 清理
- `bus_travel_avg`
  - 主鍵：`(sub_route_uid, direction, stop_uid, hour, day_of_week)`
  - `avg_seconds`：各路線、方向、站點、時段的旅行時間中位數
  - `sample_count = 0`：GTFS 冷啟動種子（`scripts/gtfs_seed.py`），會被觀測資料覆蓋
  - `sample_count > 0`：每日 04:00 `computeTravelAvg` 從 `bus_eta_history` 計算後 upsert

### vector
- `search_vector`
  - 欄位：`type`, `uid`, `name`, `city`, `depart`, `destin`, `geom`, `embedding vector(1024)`, `updated_at`
  - 唯一鍵：`(type, uid, city)`
  - `embedding` 欄位使用 pgvector，HNSW 索引（cosine），取代舊的 `blob bytea`
  - type 值：`bus_route`, `bus_station`, `bike_station`, `mrt_station`, `tra_station`, `thsr_station`, `tra_train`, `thsr_train`

## PowerSync（離線鏡像）

`app/lib/core/powersync/powersync_service.dart` 的 Schema 宣告哪些表同步到裝置本機 SQLite；`powersync/sync-rules.yaml` 的 bucket data query 決定實際同步內容（欄位別名須與 Schema 欄位名一致，PowerSync 以 query 的 `FROM` 表名命名本機表）。兩者必須一致，由 `app/test/core/powersync/sync_rules_contract_test.dart` 強制檢查（含反向檢查：repository 實際查詢的表/欄位是否都已宣告，見該檔的 `_repositoryQueries` 清單）。

目前同步表：
- `mrt_journey_matrix`（捷運票價/時間矩陣，`MrtRepository.journeyMatrix`）
- `mrt_schedule`（捷運首末班車，`MrtRepository.schedule`）
- `search_vector`（離線搜尋，`SearchRepository._searchLocal`；只同步 `type/uid/name/city/depart/destin`，`embedding`/`geom` 不同步——PowerSync column type 只有 text/integer/real，且裝置端不需要向量搜尋）
- `tra_stations` / `thsr_stations`（台鐵/高鐵站名→station_id 查詢，`TraRepository.stationId`/`ThsrRepository.stationId`；只同步 `station_id` 與 `name AS station_name`，不含 `city`/`geom`）

對應的 Postgres publication 設定見 `migrations/2026-07-17-powersync-publication-schema-scoped.sql`（取代 `migrations/2026-07-14-powersync-publication-add-synced-tables.sql` 的 `public` 硬編）。

## Redis key 格式

| Key | TTL | 說明 |
|-----|-----|------|
| `weather:{city}` | 15m | 天氣快照（JSON：temperature, precipitation, wind_speed, humidity）；`weatherSync` 寫入 |
| `bus_eta_station:{city}:{stationName}` | 180s | 公車站牌 ETA（protobuf Bus_StationArrival） |
| `bus_eta_route:{subRouteUID}` | 180s | 公車路線 ETA（protobuf Bus_RouteArrival）；有 Publish |
| `bike_availability:{stationUID}` | 2m | 自行車即時狀態（protobuf BikeEta） |
| `mrt_live:{system}:{stationId}:{lineId}` | 2m | 捷運即時班次，各線獨立存 |
| `mrt_live:{system}:{stationId}` | — | Pub/Sub channel，所有線更新都推到此頻道 |
| `tra:liveboard:{stationId}` | 3m | 台鐵即時動態（protobuf Tra_LiveBoards） |
| `tra:delay_all` | 3m | 全線誤點（protobuf TraDelays） |
| `tra:delay` | 3m | 各列車誤點（Redis Hash, trainNo → delayMins） |
| `thsr_seats:{date}:{trainNo}` | 15m | 高鐵即時座位（protobuf ThsrAvailableSeats）；有 Publish |
| `lock:bus_eta` | 28s | BusEta 分散式鎖（防止並行重複執行） |
| `lock:mrt_eta` | 9s | mrtEta 分散式鎖 |

## 索引

| 表 | 索引 | 欄位 |
|---|---|---|
| `tra_timetable` | `idx_tra_timetable_station` | `(stationid, train_date, arrivaltime)` |
| `thsr_timetable` | `idx_thsr_timetable_station` | `(stationid, train_date, arrivaltime)` |
| `bus_station_stop_map` | `idx_bssm_station_name` | `(station_name)` |
| `bus_eta_history` | `idx_eta_history_recorded` | `(recorded_at)` |
| `search_vector` | `idx_search_vector_name_trgm` | `USING gin (name gin_trgm_ops)`，需 `pg_trgm` |

## 常見讀寫行為
- `bus_static` 以 `sub_route_uid` 查詢 protobuf bytes；票價（`Bus_Fare`）內含於此 protobuf
- `bus_stations` 以地理距離排序查詢近站
- `tra_timetable` 與 `thsr_timetable` 依 `train_date` 與 `station_id` 查詢
- `tra_fares` 與 `thsr_fares` 依起迄站查詢
- 高鐵即時座位：Router SCAN `thsr_seats:{date}:*` 取初始值，再 PSubscribe 接收更新
- 捷運 ETA：Router SCAN `mrt_live:{system}:{stationId}:*` 取初始值，再 Subscribe 接收更新
