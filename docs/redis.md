made by claude
# Redis 規格

跨 binary 的 key/頻道一律經由 `services/shared/keys.go` 的建構函式產生（functions 寫、router 讀）；本文件描述 payload 與 TTL，key 格式以該檔為準。

## 連線
- 位址透過 `REDIS_ADDR` 設定
- DB 使用預設 index 0

## Pub/Sub 頻道
- Bus
  - `bus_eta_route:{sub_route_uid}`
  - `bus_eta_station:{city}:{station_name}`
- Bike
  - `bike_availability:{station_uid}`
- MRT
  - `mrt_live:{system}:{station_id}`
- TRA
  - `tra:delay:all`
  - `tra:delay:{train_no}`
- MQTT Alert（由 TDX MQTT 訂閱寫入）
  - `mqtt:v2:Bus:News:City:{city}`
  - `mqtt:v2:Bus:News:InterCity`
  - `mqtt:v2:Rail:Metro:Alert:{system}`
  - `mqtt:v3:Rail:TRA:Alert`
  - `mqtt:v2:Rail:THSR:AlertInfo`

## 快取 key
- Bus ETA Prediction
  - `weather:{city}`（天氣快照 JSON，`weatherSync` 寫入）
- Bus
  - `bus_daily_timetable:{sub_route_uid}`
- TRA
  - `TRA_Fare:{origin_station_id}:{destination_station_id}`
  - `TRA_timetable:{date}:{origin_station_id}:{destination_station_id}`
  - `TRA_Stoptimes:{date}:{train_no}`
- THSR
  - `THSR_Fare:{origin_station_id}:{destination_station_id}`
  - `THSR_timetable:{date}:{origin_station_id}:{destination_station_id}`
  - `THSR_Stoptimes:{date}:{train_no}`
  - `thsr_seats:{date}:{train_no}`（即時 AvailableSeatStatus 快照；由 `services/functions` 的 `thsr_seats` live job 每 10 分鐘寫入。builder：`shared.ThsrSeatsKey`）
  - `thsr_seats:{date}:*`（每日一個 Pub/Sub 頻道字串：live job 以此字串 PUBLISH 每列車快照，router 的 `AvailableSeats` 以同字串 SUBSCRIBE 並用它 SCAN 上面的 per-train key 做 seed。此處「`*`」是雙方共用的字面頻道名，非 glob。builder：`shared.ThsrSeatsPattern`）
- TDX 用戶端（`shared/tdx.go` 的 `TDXClient` 使用；key builder 在 `shared/keys.go`）
  - `shared:tdx:access_token`：OAuth bearer token（命名空間版；legacy fallback `TDX_Token`，401 時兩者一併刪除）。builder：`shared.TDXTokenKey` / `TDXTokenKeyLegacy`
  - `shared:raw:last_modified:{name}`：ingestor 的 If-Modified-Since 標記。builder：`shared.TDXRawIMSKey`
  - `LastTimeGet_{name}`：legacy prod 轉換路徑與 `services/functions` live job（含 THSR 座位抓取，`name=thsr_availableseats`）的 If-Modified-Since 標記。builder：`shared.TDXLegacyIMSKey`

## Hash key
- `tra:delay`
  - key：`train_no`
  - value：`delay` (秒)

## MQTT 快取 key
- `mqtt:v2:Bus:News:City:{city}`
- `mqtt:v2:Bus:News:InterCity`
- `mqtt:v2:Rail:Metro:Alert:{system}`
- `mqtt:v3:Rail:TRA:Alert`
- `mqtt:v2:Rail:THSR:AlertInfo`

## TTL
- Bus ETA
  - `bus_eta_route:*`：180 秒
  - `bus_eta_station:*`：180 秒
- Bike ETA
  - `bike_availability:*`：120 秒
- MRT LiveBoard
  - `mrt_live:*`：120 秒
- TRA Delay
  - `tra:delay:all`：180 秒  ← Pub/Sub channel（A5 已修正 _all → :all）
  - `tra:delay`：180 秒（hash，trainNo → delay 秒數）
- Bus DailyTimetable
  - `bus_daily_timetable:*`：23.5 小時
- MQTT Alert
  - `mqtt:v2:Bus:News:*`：5 分鐘
  - `mqtt:v2:Bus:News:InterCity`：5 分鐘
  - `mqtt:v2:Rail:Metro:Alert:*`：5 分鐘
  - `mqtt:v3:Rail:TRA:Alert`：5 分鐘
  - `mqtt:v2:Rail:THSR:AlertInfo`：5 分鐘
- Fares/Timetables
  - `TRA_Fare:*`：8 小時
  - `THSR_Fare:*`：1 小時
  - `TRA_timetable:*`：1 小時
  - `THSR_timetable:*`：1 小時
  - `TRA_Stoptimes:*`：1 小時
  - `THSR_Stoptimes:*`：1 小時
  - `thsr_seats:*`：15 分鐘
- TDX token / If-Modified-Since
  - `shared:tdx:access_token`：6 小時
  - `shared:raw:last_modified:*`、`LastTimeGet_*`：無 TTL（以 If-Modified-Since 語意覆寫）
- MaaS 路程規劃快取
  - `maas:plan:{sha256_hex8}`：90 秒
- Bus ETA Prediction
  - `weather:{city}`：15 分鐘
