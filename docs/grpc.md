made by claude
# gRPC 服務規格

## 服務列表
- Bus_Route_Service
- Bus_Station_Service
- Bike_Service
- Mrt_Service
- TRA_station_service
- TRA_timetable_service
- TRA_Detain_service
- Thsr_timetable_service
- Thsr_Detain_service
- Near_Station_Service
- Alert_Service
- MaasService
- Feedback_Service

## Bus_Route_Service (`models/bus.proto`)
### static
- RPC：`static(Bus_Ask_Route) -> Resp_Bus_static`
- 輸入
  - `SubRouteUID`：子路線 UID
- 行為
  - 先查 process 內 TTL cache（key `bus_static:{sub_route_uid}`，TTL 1h）
  - Miss 時查詢 `bus_static` 表並回寫 cache
  - 回傳 protobuf bytes
- 依賴
  - PostgreSQL

### daily
- RPC：`daily(Bus_Ask_Route) -> Resp_Bus_daily_timetable`
- 輸入
  - `SubRouteUID`
- 行為
  - 從 Redis 讀取日班次
- Redis key
  - `bus_daily_timetable:{sub_route_uid}`

### eta
- RPC：`eta(Bus_Ask_Route) -> stream Resp_Bus_eta`
- 輸入
  - `SubRouteUID`
- 行為
  - 訂閱 Redis Pub/Sub 並串流
- Redis channel
  - `bus_eta_route:{sub_route_uid}`

## Bus_Station_Service (`models/bus.proto`)
### eta
- RPC：`eta(Bus_Ask_Route) -> stream Resp_Bus_eta`
- 輸入
  - `SubRouteUID` 以 `city:station_name` 格式傳入
- 行為
  - 解析 `city` 與 `station_name`
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `bus_eta_station:{city}:{station_name}`

## Bike_Service (`models/bike.proto`)
### static
- RPC：`static(Bike_request) -> Bike_static`
- 輸入
  - `StationUID`
- 行為
  - 先查 process 內 TTL cache（key `bike_static:{station_uid}`，TTL 1h）
  - Miss 時查詢 `bike_stations` 表並回寫 cache
  - 回傳 protobuf bytes

### eta
- RPC：`eta(Bike_request) -> stream Resp_Bike_eta`
- 輸入
  - `StationUID`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `bike_availability:{station_uid}`

## Mrt_Service (`models/mrt.proto`)
### eta
- RPC：`eta(Ask_mrt) -> stream Resp_Mrt_eta`
- 輸入
  - `system`
  - `StationID`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mrt_live:{system}:{station_id}`

## TRA_timetable_service (`models/tra.proto`)
### timetable
- RPC：`timetable(ask_route) -> tra_timetable`
- 輸入
  - `date`
  - `origin_station_id`
  - `destination_station_id`
- 行為
  - Redis 查詢，不存在時以單一 `WHERE stationid = ANY($1) AND train_date = $2 AND arrivaltime >= $3` 同時取起迄站資料，在 Go 側依 `stationid` 分流；仍為空時才呼叫 TDX API
- Redis key
  - `TRA_timetable:{date}:{origin_station_id}:{destination_station_id}`

### fare
- RPC：`fare(ask_staiton) -> TraFareItem`
- 輸入
  - `station_id` 為 `origin_station_id`
  - `date` 為 `destination_station_id`
- 行為
  - Redis 查詢，不存在時觸發 DB/API 更新
- Redis key
  - `TRA_Fare:{origin_station_id}:{destination_station_id}`

### delay
- RPC：`delay(ask_route) -> stream Resp_tra_delay`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `tra:delay:all`

### station_board
- RPC：`station_board(ask_station_board) -> tra_station_board`
- 輸入
  - `station_id`（數字站碼或站名，站名走 `resolveRailStationID` 的 臺/台 相容解析）
  - `date`
  - `after`（`HH:mm:ss` 發車時間下界；由呼叫端帶自己的時鐘，router 跑在 UTC）
  - `direction`（0 順行 / 1 逆行）
  - `limit`（0 = 預設 20，上限 50）
- 行為
  - 讀 `tra_timetable`，排除以本站為終點的班次（發車看板不列無法上車的到站班次）
  - Redis 快取「整個服務日」的看板，時間窗在 handler 切；同一站同方向的乘客共用一份
  - 當日剩餘班次不足 `limit` 時，往後補次日班次（深夜開啟時只剩兩班不算答案）；每列自帶 `TrainDate`
  - 該日完全沒有資料才回 `NotFound`；已落地但當日班次跑完會回空看板，兩者在 app 上是不同訊息
- Redis key
  - `TRA_StationBoard:{date}:{station_id}:{direction}`

## TRA_Detain_service (`models/tra.proto`)
### stops
- RPC：`stops(ask_detain) -> tra_stoptimes`
- 輸入
  - `date`
  - `trainno`
- 行為
  - Redis 查詢，不存在時觸發 DB/API 更新
- Redis key
  - `TRA_Stoptimes:{date}:{train_no}`

### delay
- RPC：`delay(ask_detain) -> stream Resp_tra_delay`
- 輸入
  - `trainno`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `tra:delay:{train_no}`

## Thsr_timetable_service (`models/thsr.proto`)
### fare
- RPC：`fare(Ask_Thsr) -> thsa_fare`
- 輸入
  - `origin_station_id`
  - `destination_station_id`
- 行為
  - Redis 查詢，不存在時觸發 DB/API 更新
- Redis key
  - `THSR_Fare:{origin_station_id}:{destination_station_id}`

### timetable
- RPC：`timetable(Ask_Thsr) -> thsr_timetables`
- 輸入
  - `date`
  - `origin_station_id`
  - `destination_station_id`
- 行為
  - Redis 查詢，不存在時以單一 `WHERE stationid = ANY($1) AND train_date = $2` 同時取起迄站資料，在 Go 側依 `stationid` 分流，出發站依時間過濾；仍為空時才呼叫 TDX API
- Redis key
  - `THSR_timetable:{date}:{origin_station_id}:{destination_station_id}`

### station_board
- RPC：`station_board(thsr_ask_station_board) -> thsr_station_board`
- 輸入
  - `station_id`、`date`、`after`、`direction`（0 南下 / 1 北上）、`limit`
- 行為
  - 與 TRA `station_board` 相同：讀 `thsr_timetable`、快取整日、深夜補次日、NotFound 只代表該日未落地
- Redis key
  - `THSR_StationBoard:{date}:{station_id}:{direction}`

## Thsr_Detain_service (`models/thsr.proto`)
### stops
- RPC：`stops(thsr_ask_detain) -> thsr_stoptimes`
- 輸入
  - `date`
  - `trainno`
- 行為
  - Redis 查詢，不存在時觸發 DB/API 更新
- Redis key
  - `THSR_Stoptimes:{date}:{train_no}`

## Alert_Service (`models/alert.proto`)

來源：TDX MQTT 訊息，由 `services/functions` 接收後**正規化**再存入 Redis
Pub/Sub。TDX 三種 payload 形狀（裸陣列、`{"Alerts":[...]}` 信封、單一物件）在寫入
時就攤平成 `Alert_Msg { repeated Alert_Item items }`，router 只做 protojson →
proto 的轉型，app 端不再解析任何 TDX 欄位名（ADR-0016）。

每則訊息是該 channel 的**當前快照**，不是增量：訂閱者應以整批取代該來源既有的
告警，TDX 不再發布的那則即代表已排除。

`Alert_Item.route_keys` 是該告警的適用範圍（公車子路線、台鐵車次、捷運路線）；
空陣列代表未指名路線，屬全系統告警。

### busNews
- RPC：`busNews(Alert_Bus_Ask) -> stream Alert_Msg`
- 輸入
  - `city`：城市代碼（如 `Taipei`）
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mqtt:v2:Bus:News:City:{city}`

### busAlert
- RPC：`busAlert(Alert_Bus_Ask) -> stream Alert_Msg`
- 輸入
  - `city`：城市代碼（如 `Taipei`）
- 行為
  - 訂閱 Redis Pub/Sub 串流。與 `busNews` 分開是因為 TDX 把公告與通阻發在不同
    topic，各自鏡射自己的 latest-payload key；合流會讓後寫的那類決定新訂閱者
    看到什麼
- Redis channel
  - `mqtt:v2:Bus:Alert:City:{city}`

### metroAlert
- RPC：`metroAlert(Alert_Metro_Ask) -> stream Alert_Msg`
- 輸入
  - `system`：捷運系統代碼（如 `TRTC`、`KRTC`、`KLRT`、`TYMC`）
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mqtt:v2:Rail:Metro:Alert:{system}`

### traAlert
- RPC：`traAlert(Alert_Ask) -> stream Alert_Msg`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mqtt:v3:Rail:TRA:Alert`

### thsrAlert
- RPC：`thsrAlert(Alert_Ask) -> stream Alert_Msg`
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mqtt:v2:Rail:THSR:AlertInfo`

## Near_Station_Service (`models/near.proto`)
### near
- RPC：`near(stream Ask_Near) -> stream resp_near`
- 輸入
  - `PositionLon`
  - `PositionLat`
  - `Radius`
- 行為
  - 5 種站型（Bus/Bike/MRT/TRA/THSR）以獨立 goroutine 並行查詢，`sync.WaitGroup` 收集結果
  - OSRM 呼叫（`http://osrm:5000/table/v1/foot/`）使用 server 共用的 `*resty.Client`
  - `NearStation.Type`：1=Bus, 2=Bike, 3=MRT, 4=TRA, 5=THSR
  - 回傳多種交通型態的集合

## MaasService (`models/maas.proto`)
### plan
- RPC：`plan(MaasPlanRequest) -> MaasPlanResponse`
- 輸入
  - `fromLat`, `fromLon`：起點 WGS-84 座標
  - `toLat`, `toLon`：終點 WGS-84 座標
  - `date`：YYYY-MM-DD
  - `time`：HH:MM:SS
  - `arriveBy`：true=到達時間，false=出發時間（預設）
- 行為
  - 呼叫 TDX MaaS API (`https://tdx.transportdata.tw/api/maas`)
  - `singleflight` 去重並發請求
  - 結果快取至 Redis (`maas:plan:{hash}`) 90 秒
- 回傳
  - `Itinerary[]`：每筆含 duration(秒)、transfers、legs[]
  - `Leg.mode`：WALK/BUS/SUBWAY/RAIL/TRAM/FERRY
- Redis key
  - `maas:plan:{sha256_hex8}` TTL 90 s

### planStream
- RPC：`planStream(MaasPlanRequest) -> stream MaasPlanUpdate`
- 與 `plan` 同一份查詢，但**分兩則訊息**送出。App 目前一律走這條；unary `plan` 保留給已上架的舊版本。
- 分段的位置
  1. `complete=false`：TDX 路線 + 票價 + 通知識別（`convertRoutes`）。結果清單需要的東西全在這裡，卡片畫得出來、按得下去。
  2. `complete=true`：補上 OSRM 步行路徑與軌道線形（`enrichGeometry`）。這段慢，而且只有地圖上的線需要它——section 的 `walkPath` / `transitPath` 為空時 App 本來就會退回直線。
- 快取命中只送一則 `complete=true`。
- 行為差異
  - **不走 singleflight**：同一分鐘內兩筆完全相同的查詢可能各打一次 TDX，由 90 秒快取與 4 個 work slot 收斂。要讓等待者也收到 leader 的第一則訊息得做 per-key broadcast，那是為了極少發生的碰撞（同座標、同選項、同分鐘）而加的機制。
  - 客戶端斷線會取消 work context（`context.AfterFunc`），不像 unary 那樣把工作留給其他等待者。
  - 幾何補完後、送出最後一則之前就寫快取：工作已經付出代價，不因為對方剛好斷線而丟掉。
- 配額：`plan` 與 `planStream` 共用同一個 rate-limiter bucket（`maasQuotaScope`）。分開計會讓呼叫端換個方法就多拿一份 TDX 額度。

## Feedback_Service (`models/feedback.proto`)
### postFeedback
- RPC：`postFeedback(PostFeedbackRequest) -> FeedbackReceipt`
- 輸入
  - `install_id`：匿名安裝識別（與 `firebase_device` 同一組，但**不是** FK——關掉推播或裝置列被清掉的使用者仍要能回報）
  - `category`：`route_data` | `eta` | `crash` | `suggestion`，伺服器與 `feedback_thread` 的 CHECK 兩邊都限制
  - `body`：自由文字，上限 2000 runes（不是 bytes：中文報告用 byte 上限只剩三分之一可用長度）
  - `diagnostics`：`app_version` / `platform` / `os_version` / `screen` / `locale`，每欄 128 字元上限，空值不寫入
- 驗證
  - 與其他 device-scoped RPC 相同：`x-install-id` + `x-install-secret` metadata 比對 `firebase_device.install_secret_hash`（共用 `authorizeInstallation`）
  - 這道驗證是配額有意義的前提——未驗證的呼叫端可以每次換一組 `install_id`
- 行為
  - thread 與開頭 message 以**單一 statement**（data-modifying CTE）寫入，兩者同時成立或同時不成立
  - 每個 install 24 小時內上限 10 則，配額寫在 INSERT 的 WHERE 裡而非前一句 SELECT，所以兩個並行請求無法各自讀到未達上限的計數後都寫入；配額用盡 → `ResourceExhausted`
  - 寫入成功後以獨立 goroutine POST 到 `FEEDBACK_WEBHOOK_URL`（Discord shape，`allowed_mentions.parse = []` 讓使用者文字無法 ping 頻道）。**通知不是成功條件**：已寫進 Postgres 的回報就是收到了，webhook 連不上只留一行 log
- 回傳
  - `thread_id`（UUID）、`created_at_unix`
  - App 顯示 `thread_id` 的第一段作為使用者可引用的回報編號；那是查詢前綴，不是鍵，所以沒有任何東西以它為索引
