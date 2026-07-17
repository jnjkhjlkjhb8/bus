# Remote Config 規格文件

本文件記錄 Flutter 前端目前已接線的 Firebase Remote Config 參數。新參數等到實際需要時再接線、再補進下表。

---

## 現有 Remote Config 狀態

Firebase Remote Config 在 `core/firebase/firebase_bootstrap.dart` 初始化：`setDefaults(AppConfig.defaults)` + `fetchAndActivate()`（fetch timeout `5` 秒，最小 fetch interval `1` 小時）。

**讀取一律走 `core/firebase/remote_config.dart` 的 `AppConfig`**——薄靜態 accessor（`getBool` / `getString` / `getInt`）。`FirebaseGate.enabled` 為 false（dev/test flavor）或讀取拋錯時，一律回退到 `AppConfig.defaults`，所以任何層都能安全讀取，dev/test 不需要 Firebase。`AppConfig.defaults` 是預設值的單一來源，同時餵給 `setDefaults()`，避免註冊值與回退值漂移。

線上 template：`remoteconfig.template.json`（`firebase deploy --only remoteconfig`，專案 `mybus-32985`）。

### 已接線

| Key | 型別 | 預設 | 消費點 |
|---|---|---|---|
| `maintenance_banner_enabled` | `bool` | `false` | `shared/widgets/maintenance_banner.dart`（全域頂部橫幅，靜態、不可關） |
| `maintenance_banner_text` | `String` | `''` | 同上（enabled 且非空才顯示） |
| `push_enabled` | `bool` | `true` | `firebase_bootstrap.dart` `updatePushPreference`——remote kill switch，false 則不啟用推播 |
| `min_supported_version` | `String` | `'1.0.0'` | `core/update/force_update.dart` `ForceUpdateGate`——低於此版本顯示阻擋畫面；semver 比較器 **fail-open**（解析失敗不鎖用戶） |
| `store_url_ios` / `store_url_android` | `String` | `''` | 強制更新畫面「前往更新」按鈕；空則隱藏按鈕但仍阻擋 |
| `eta_approaching_threshold_s` | `int` | `30` | `bus_route_data_helpers.dart` + `metro_eta_bloc.dart`（「即將到站」門檻） |
| `alert_sources` | `String` | `'metro:TRTC,bus:Taipei'` | `alert_bloc.dart` `parseAlertSources`——tagged token（見下），擴展城市免發版 |
| `nearby_fallback_radius_m` | `int` | `900` | `home_marker_helpers.dart`（地圖 controller 未就緒時的回退半徑） |

> **`alert_sources` 格式變更**：舊值 `'TRTC,Taipei'` 無法區分 metro 系統與巴士城市（分別呼叫 `metroAlert()` / `busNews()`），改為 tagged token `metro:<系統>,bus:<城市>`（逗號分隔，可多個）。TRA/THSR 是全國性鐵路、直接寫死不列於此。無效或未知 kind 的 token 會被丟棄（壞值不會讓告警啟動失敗）。線上值已同步 deploy。

> **`arrival_lead_minutes`（原 #5）尚未接線**：到站提醒功能本身是 stub（鈴鐺只切 bloc state，沒有任何地方真的排提醒），需先補完提醒管線才談得上讀此 key，另開設計。

