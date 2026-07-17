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

來源：TDX MQTT 訊息，由 `server/functions` 接收後存入 Redis Pub/Sub。
串流資料為 TDX 原始 JSON（`bytes data`）。

### busNews
- RPC：`busNews(Alert_Bus_Ask) -> stream Alert_Msg`
- 輸入
  - `city`：城市代碼（如 `Taipei`）
- 行為
  - 訂閱 Redis Pub/Sub 串流
- Redis channel
  - `mqtt:v2:Bus:News:City:{city}`

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
