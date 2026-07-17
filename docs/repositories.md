# 前端 Repository 資料層

## 概述

Repository 層封裝所有後端 gRPC 呼叫，提供給 BLoC 和 Widget 模組使用的統一資料介面。
所有 repository 都是 `const` singleton，無狀態，不持有任何快取或串流實例。

**位置：** `frontend/lib/data/repositories/`

**依賴：**
- `frontend/lib/core/grpc/grpc_client.dart` — gRPC stub singleton
- `frontend/lib/data/generated/*.pb.dart` — protobuf 訊息型別
- `frontend/lib/data/generated/*.pbgrpc.dart` — gRPC client stubs

---

## 使用模式

```dart
// 一次性查詢（Unary RPC）
final result = await BusRepository.instance.routeStatic('TPE-123');

// 即時串流（Server-streaming RPC）
final sub = BusRepository.instance.routeEta('TPE-123').listen((msg) {
  // msg.data 為 protobuf bytes，依需求自行 decode
});
// 取消時：
sub.cancel();
```

---

## Repository 清單

### BusRepository
**檔案：** `bus_repository.dart`  
**gRPC stubs：** `GrpcClient.instance.busRoute`, `busStation`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `routeStatic(subRouteUid)` | 路線靜態資料 | `Future<Resp_Bus_static>` |
| `routeDaily(subRouteUid)` | 路線當日班表 | `Future<Resp_Bus_daily_timetable>` |
| `routeEta(subRouteUid)` | 路線即時到站（streaming） | `Stream<Resp_Bus_eta>` |
| `stationEta(city, stationName)` | 站牌即時到站（streaming） | `Stream<Resp_Bus_eta>` |

`stationEta` 的 key 格式為 `"city:stationName"`，由 repository 內部組合。

回傳的 `Resp_Bus_eta.data` 是 protobuf 序列化的 `Bus_RouteArrival` 陣列，
使用 `Bus_RouteArrival.fromBuffer(msg.data)` 解碼。

---

### BikeRepository
**檔案：** `bike_repository.dart`  
**gRPC stub：** `GrpcClient.instance.bike`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `stationStatic(stationUid)` | 站點靜態資料（名稱、位置、容量） | `Future<Bike_static>` |
| `stationEta(stationUid)` | 即時可借還車數（streaming） | `Stream<Resp_Bike_eta>` |

---

### MrtRepository
**檔案：** `mrt_repository.dart`  
**gRPC stub：** `GrpcClient.instance.mrt`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `eta(system, stationId)` | 捷運站即時到站（streaming） | `Stream<Resp_Mrt_eta>` |

`system` 範例：`'TRTC'`（台北捷運）、`'KRTC'`（高雄捷運）。

---

### TraRepository
**檔案：** `tra_repository.dart`  
**gRPC stubs：** `GrpcClient.instance.traTimetable`, `traDetain`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `timetable(date, originId, destId)` | O/D 班表查詢 | `Future<tra_timetables>` |
| `fare(stationId, date)` | 票價查詢 | `Future<TraFareItem>` |
| `delay(date, originId, destId)` | 延誤資訊（streaming） | `Stream<Resp_tra_delay>` |
| `stops(date, trainNo)` | 指定車次各站時刻 | `Future<tra_stoptimes>` |
| `trainDelay(date, trainNo)` | 指定車次延誤（streaming） | `Stream<Resp_tra_delay>` |

`date` 格式：`'yyyy-MM-dd'`。`fare` 的 `stationId` 依後端慣例為 `'originId:destId'` 組合字串。

---

### ThsrRepository
**檔案：** `thsr_repository.dart`  
**gRPC stubs：** `GrpcClient.instance.thsr`, `thsrDetain`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `fare(date, originId, destId)` | 票價查詢 | `Future<thsa_fare>` |
| `timetable(date, originId, destId)` | O/D 班表查詢 | `Future<thsr_timetables>` |
| `stops(date, trainNo)` | 指定車次各站時刻 | `Future<thsr_stoptimes>` |

THSR 站點 ID 清單：`'0990'`（南港）到 `'0430'`（左營）。

---

### AlertRepository
**檔案：** `alert_repository.dart`  
**gRPC stub：** `GrpcClient.instance.alert`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `busNews(city)` | 公車服務公告（streaming） | `Stream<Alert_Msg>` |
| `metroAlert(system)` | 捷運異常通報（streaming） | `Stream<Alert_Msg>` |
| `traAlert()` | 台鐵全線異常通報（streaming） | `Stream<Alert_Msg>` |
| `thsrAlert()` | 高鐵全線異常通報（streaming） | `Stream<Alert_Msg>` |

`Alert_Msg.data` 為 TDX 原始 JSON bytes，以 `utf8.decode(msg.data)` 取得字串後再解析。
資料由 TDX MQTT 推播，後端存入 Redis Pub/Sub，詳見 `docs/ingestion.md §MQTT`。

---

### NearRepository
**檔案：** `near_repository.dart`  
**gRPC stub：** `GrpcClient.instance.near`

| 方法 | 說明 | 回傳 |
|------|------|------|
| `near(Stream<Ask_Near>)` | 雙向串流完整介面 | `Stream<resp_near>` |
| `nearOnce(lat, lon, radius)` | 單次查詢便利包裝 | `Stream<resp_near>` |

`nearOnce` 建立單元素 `StreamController`，送出一筆 `Ask_Near` 後關閉。
`radius` 單位為公尺。`resp_near` 包含附近公車站、YouBike 站、捷運站、台鐵站、高鐵站，
每站含步行時間（由後端 OSRM 計算）。

---

## Bytes 欄位解碼

多個 streaming 回傳型別的主要資料藏在 `bytes data` 欄位中（後端為節省 gRPC 傳輸
而先序列化為 bytes 再包一層）。解碼方式：

| 回傳訊息 | `data` 內容 | 解碼 |
|----------|-------------|------|
| `Resp_Bus_eta` | `Bus_RouteArrival` 列表 | `Bus_RouteArrival.fromBuffer(msg.data)` |
| `Resp_Bus_static` | `Bus_subroute` | `Bus_subroute.fromBuffer(msg.data)` |
| `Resp_Bus_daily_timetable` | 班表 | `Bus_subroute.fromBuffer(msg.data)` |
| `Resp_Mrt_eta` | `Mrt_live` 列表 | 依 `mrt.pb.dart` 型別解碼 |
| `Resp_tra_delay` | `tra_delays` | `tra_delays.fromBuffer(msg.data)` |
| `Resp_Bike_eta` | 可借還車數 | 依 `bike.pb.dart` 型別解碼 |
| `Alert_Msg` | TDX JSON | `utf8.decode(msg.data)` |

---

## 擴充原則

1. **不在 repository 裡加狀態或快取**：repository 是純粹的 gRPC 呼叫封裝；快取放 BLoC 或 Widget 層。
2. **不在 repository 裡做錯誤處理**：讓 gRPC exception（`GrpcError`）向上傳遞，由 BLoC 捕捉並轉換為 UI 狀態。
3. **Streaming 串流的生命週期由呼叫端管理**：`StreamSubscription.cancel()` 要在 BLoC 的 `close()` 或 Widget `dispose()` 時呼叫。
