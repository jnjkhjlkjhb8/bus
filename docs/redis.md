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
  - `mrt_track:events:{track_id}`（捷運下車提醒 session 的即時狀態更新；functions tracker 每站 PUBLISH，router 的 `WatchTrack` SUBSCRIBE。builder：`shared.MrtTrackChannel`；ADR-0015）
- TRA
  - `tra:delay:all`
  - `tra:delay:{train_no}`
- MQTT Alert（由 TDX MQTT 訂閱寫入；內容為正規化後的 `models.Alert_Msg`
  protojson，非 TDX 原始 payload——ADR-0016。每次寫入都是該 channel 的當前快照，
  解析失敗的 payload 會被丟棄而不覆蓋上一份，否則會清空所有人的告警清單）
  - `mqtt:v2:Bus:News:City:{city}`
  - `mqtt:v2:Bus:News:InterCity`
  - `mqtt:v2:Bus:Alert:City:{city}`
  - `mqtt:v2:Bus:Alert:InterCity`
  - `mqtt:v2:Rail:Metro:Alert:{system}`
  - `mqtt:v3:Rail:TRA:Alert`
  - `mqtt:v2:Rail:THSR:AlertInfo`

## 快取 key
- MRT 下車提醒（ADR-0015）
  - `mrt_track:state:{track_id}`（一個 session 的即時位置狀態，`models.MrtTrackState` proto；router 的 `CreateTrack` 初始化並供 `WatchTrack` seed，functions tracker 每站覆寫。builder：`shared.MrtTrackKey`）
- GTFS-RT（ADR-0019）
  - `gtfs_rt:feed`（序列化後的整份 `FeedMessage`；`services/functions` 的
    `gtfsRTBuilder` 每 30 秒覆寫，`services/router` 的
    `/api/gtfs-rt/trip-updates.pb` 原樣吐出。TTL 是刻意的存活檢查：builder 停了
    key 就過期，endpoint 回 503，規劃器退回靜態時刻表，而不是拿到一份沒人發現
    已經過期數小時的快照。builder：`shared.GTFSRealtimeKey`）
- Bus ETA Prediction
  - `weather:{city}`（天氣快照 JSON，`weatherSync` 寫入）
- Bus
  - `bus_daily_timetable:{sub_route_uid}`
- TRA
  - `TRA_Fare:{origin_station_id}:{destination_station_id}`
  - `TRA_timetable:{date}:{origin_station_id}:{destination_station_id}`
  - `TRA_Stoptimes:{date}:{train_no}`
  - `TRA_StationBoard:{date}:{station_id}:{direction}`（一站一方向的整個服務日發車看板；時間窗由 handler 切，空的一天不寫入快取）
- THSR
  - `THSR_Fare:{origin_station_id}:{destination_station_id}`
  - `THSR_timetable:{date}:{origin_station_id}:{destination_station_id}`
  - `THSR_Stoptimes:{date}:{train_no}`
  - `THSR_StationBoard:{date}:{station_id}:{direction}`
  - `thsr_seats:{date}:{train_no}`（即時 AvailableSeatStatus 快照；由 `services/functions` 的 `thsr_seats` live job 每 10 分鐘寫入。builder：`shared.ThsrSeatsKey`）
  - `thsr_seats:{date}:*`（每日一個 Pub/Sub 頻道字串：live job 以此字串 PUBLISH 每列車快照，router 的 `AvailableSeats` 以同字串 SUBSCRIBE 並用它 SCAN 上面的 per-train key 做 seed。此處「`*`」是雙方共用的字面頻道名，非 glob。builder：`shared.ThsrSeatsPattern`）
- TDX 用戶端（`shared/tdx.go` 的 `TDXClient` 使用；key builder 在 `shared/keys.go`）
  - `shared:tdx:access_token`：OAuth bearer token（命名空間版；legacy fallback `TDX_Token`，401 時兩者一併刪除）。builder：`shared.TDXTokenKey` / `TDXTokenKeyLegacy`
  - `shared:raw:last_modified:{name}`：ingestor 的 If-Modified-Since 標記。builder：`shared.TDXRawIMSKey`
  - `LastTimeGet_{name}`：legacy prod 轉換路徑與 `services/functions` live job（含 THSR 座位抓取，`name=thsr_availableseats`）的 If-Modified-Since 標記。builder：`shared.TDXLegacyIMSKey`

## Hash key
- `tra:delay`
  - key：`train_no`
  - value：`delay`（**分鐘**，TDX `LiveTrainDelay.DelayTime` 的原值；App 以
    `Duration(minutes:)` 讀取。任何以秒為單位的下游都必須自行換算——GTFS-RT
    的 `delay` 是秒，`gtfs_rt_delay.go` 乘 60）
- `tra:delay:station`
  - key：`train_no`
  - value：`StationID`（該筆誤點是在哪一站量到的）
  - 與 `tra:delay` 同一個 pipeline 寫入、同 TTL。分成兩個 hash 而不是把值變複雜，
    是因為 App 把 `tra:delay` 的值當純數字讀；只有 GTFS-RT 需要知道觀測地點，
    用來把誤點掛在某一站而不是整列車上

## MQTT 快取 key
- `mqtt:v2:Bus:News:City:{city}`
- `mqtt:v2:Bus:News:InterCity`
- `mqtt:v2:Bus:Alert:City:{city}`
- `mqtt:v2:Bus:Alert:InterCity`
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
- MRT 下車提醒 session 狀態（ADR-0015）
  - `mrt_track:state:*`：進行中 3 小時（對齊 reminder 的 `expires_at`），結束（arrived/lost/stale/cancelled）後縮為 60 秒讓已連線的 watcher 收到最終狀態後過期
- TRA Delay
  - `tra:delay:all`：180 秒  ← Pub/Sub channel（A5 已修正 _all → :all）
  - `tra:delay`：180 秒（hash，trainNo → delay **分鐘**）
  - `tra:delay:station`：180 秒（hash，trainNo → 觀測站 StationID）
- Bus DailyTimetable
  - `bus_daily_timetable:*`：23.5 小時
- GTFS-RT
  - `gtfs_rt:feed`：3 分鐘（重建週期 30 秒的數倍，慢一拍不會讓 feed 變空，
    但 builder 真的死了會在幾分鐘內變成 503 而非繼續供應舊資料）
- MQTT Alert
  - `mqtt:v2:Bus:News:*`：5 分鐘
  - `mqtt:v2:Bus:News:InterCity`：5 分鐘
  - `mqtt:v2:Bus:Alert:*`：5 分鐘
  - `mqtt:v2:Rail:Metro:Alert:*`：5 分鐘
  - `mqtt:v3:Rail:TRA:Alert`：5 分鐘
  - `mqtt:v2:Rail:THSR:AlertInfo`：5 分鐘
- 告警推播去重（`fcm:alert:{route_type}\0{route_key}\0{body hash}`）
  - 24 小時。TDX 會把同一則持續中的災情反覆重發、斷線重連也會重收 retained
    訊息，窗口若短於災情本身就會重複通知；鍵取內容雜湊而非 TDX 的
    `AlertID`/`UpdateTime`，後者在文字沒變時仍會改變（ADR-0016）
- Fares/Timetables
  - `TRA_Fare:*`：8 小時
  - `THSR_Fare:*`：1 小時
  - `TRA_timetable:*`：1 小時
  - `THSR_timetable:*`：1 小時
  - `TRA_Stoptimes:*`：1 小時
  - `THSR_Stoptimes:*`：1 小時
  - `TRA_StationBoard:*`：1 小時
  - `THSR_StationBoard:*`：1 小時
  - `thsr_seats:*`：15 分鐘
- TDX token / If-Modified-Since
  - `shared:tdx:access_token`：6 小時
  - `shared:raw:last_modified:*`、`LastTimeGet_*`：無 TTL（以 If-Modified-Since 語意覆寫）
- MaaS 路程規劃快取
  - `maas:plan:{sha256_hex8}`：90 秒
- Bus ETA Prediction
  - `weather:{city}`：15 分鐘
