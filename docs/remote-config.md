# Remote Config 規格文件

本文件記錄 Flutter 前端目前已接線的 Firebase Remote Config 參數。新參數等到實際需要時再接線、再補進下表。

---

## 現有 Remote Config 狀態

Firebase Remote Config 在 `core/firebase/firebase_bootstrap.dart` 初始化：`setDefaults(AppConfig.defaults)` + `fetchAndActivate()`（fetch timeout `5` 秒，最小 fetch interval `1` 分鐘，並訂閱 Realtime `onConfigUpdated`）。

**讀取一律走 `core/firebase/remote_config.dart` 的 `AppConfig`**——薄靜態 accessor（`getBool` / `getString` / `getInt`）。`FirebaseGate.enabled` 為 false（dev/test flavor）或讀取拋錯時，一律回退到 `AppConfig.defaults`，所以任何層都能安全讀取，dev/test 不需要 Firebase。`AppConfig.defaults` 是預設值的單一來源，同時餵給 `setDefaults()`，避免註冊值與回退值漂移。

線上 template：`remoteconfig.template.json`（`firebase deploy --only remoteconfig`，專案 `mybus-32985`）。

### 已接線

| Key | 型別 | 預設 | 消費點 |
|---|---|---|---|
| `maintenance_banner_enabled` | `bool` | `false` | `alert_bloc.dart` `readAnnouncements` → `NoticeRailHost`（常駐頂部通知列，不可關） |
| `maintenance_banner_text` | `String` | `''` | 同上（enabled 且非空才顯示） |
| `announcement_text` | `String` | `''` | `alert_bloc.dart` `readAnnouncements`——全體公告，非空才發布（無獨立開關） |
| `push_enabled` | `bool` | `true` | `firebase_bootstrap.dart` `updatePushPreference`——remote kill switch，false 則不啟用推播 |
| `min_supported_version` | `String` | `'1.0.0'` | `core/update/update_gate.dart` `UpdateGate`——低於此版本顯示阻擋畫面；semver 比較器 **fail-open**（解析失敗不鎖用戶） |
| `latest_version` | `String` | `'1.0.0'` | 同上——低於此版本但仍在支援範圍內時，`NoticeRailHost` 顯示可關閉的更新提醒；亦供 設定 › 檢查更新 比對 |
| `store_url_ios` / `store_url_android` | `String` | `''` | 強制更新畫面與更新提醒的「前往更新」；空或不合法則不出按鈕（絕不留死連結） |
| `eta_approaching_threshold_s` | `int` | `30` | `bus_route_data_helpers.dart` + `metro_eta_bloc.dart`（「即將到站」門檻） |
| `alert_sources` | `String` | `'metro:TRTC,bus:Taipei'` | `alert_bloc.dart` `parseAlertSources`——tagged token（見下），擴展城市免發版 |
| `nearby_fallback_radius_m` | `int` | `900` | `home_marker_helpers.dart`（地圖 controller 未就緒時的回退半徑） |
| `genui_enabled` | `bool` | `true` | `genui_ask_lane.dart` `GenUiAskLane.enabled`——搜尋頁「問問看」車道的 kill switch，false 則整條車道不渲染（關鍵字搜尋不受影響）。與 `FirebaseGate.enabled` 相 and，dev/test flavor 本來就沒有。 |
| `genui_system_prompt` | `String` | 見 `remote_config.dart` `AppConfig.defaults` | `genui_service.dart` `GenUiService._systemPrompt`——問問看模型的系統提示詞，可在不發版的情況下修正提示詞問題。**改這個值前先讀程式碼**：提示詞裡點名的工具名稱（`searchTransit`/`renderUI`）與節點種類（`heading`/`text`/`route`/`step`/`chip`/`divider`）是程式寫死接的，線上改壞名稱或拿掉某個節點種類只會讓模型叫不動工具或吐出解析不了的節點，不是文字上的小事。 |

> **`alert_sources` 格式變更**：舊值 `'TRTC,Taipei'` 無法區分 metro 系統與巴士城市（分別呼叫 `metroAlert()` / `busNews()`），改為 tagged token `metro:<系統>,bus:<城市>`（逗號分隔，可多個）。TRA/THSR 是全國性鐵路、直接寫死不列於此。無效或未知 kind 的 token 會被丟棄（壞值不會讓告警啟動失敗）。線上值已同步 deploy。

> **`announcement_text` 是全體廣播的唯一發布口**：文字非空即發布，不需要另一個 enable 旗標。它不是獨立橫幅，而是被 `readAnnouncements()` 包成 `AlertViewModel(source: appNotice)` 送進 `AlertBloc`，跟捷運／公車告警共用同一個通知中心、未讀徽章與已讀狀態；`NoticeKind.announcement` 讓它永遠是 `NoticeTone.info`（要 caution 請改用維護橫幅），且 `dismissible` 為 true，使用者可自行清除。**文字即身分**——改寫內容等同發布一則新公告並重新點亮所有人的未讀，這正是改稿時要的行為。
>
> 相對地，`maintenance_banner_*` 走 Remote Config 而非後端串流是刻意的：後端掛掉時告警串流也一起掛，那正是最需要對使用者說話的時刻。維護橫幅必須獨立於 router 存活。

> **`arrival_lead_minutes`（原 #5）尚未接線**：到站提醒功能本身是 stub（鈴鐺只切 bloc state，沒有任何地方真的排提醒），需先補完提醒管線才談得上讀此 key，另開設計。


---

## 更新系統（強制 / 提醒 / 灰度）

三檔共用 `core/update/update_status.dart` 的比較器與 store URL allowlist，所以三個介面不可能對「裝了哪一版」有不同看法。

| 檔位 | 判斷 | 介面 | 可關 |
|---|---|---|---|
| 強制 | `目前版本 < min_supported_version` | 全螢幕阻擋畫面（`PopScope`，無法返回） | 不可 |
| 提醒 | `min ≤ 目前版本 < latest_version` | `NoticeRailHost` 條件列，附「前往更新」 | 可，記住該版本 |
| 靜默 | 以上皆非 | 無 | — |

`UpdateGate` 是唯一的版本檢查點：掛載時檢查一次，之後每個 Remote Config revision 再檢查一次（含 Realtime 推送與 設定 › 檢查更新 觸發的 fetch），所以線上調整不需要使用者重開 app。強制優先於提醒——低於下限時提醒會被清掉，不會在阻擋畫面後面留一條可關的通知列。

**提醒的關閉是 per-version 的**：關掉只對當下那個 `latest_version` 生效（寫進 Hive `dismissed_update_version`），發下一版就會再提醒一次。刻意沒有「N 天後再提醒」這一層。

**平台共用單一 key**：iOS / Android 兩邊審核時程不同，但 `min_supported_version` 與 `latest_version` 都是共用的。**ops 必須等兩邊都上架後才調整**，否則會提醒（或擋掉）一邊去下載一個還不存在的版本。

### 灰度發布

`latest_version` 的灰度走 Remote Config **Conditions**，不是 app 端的邏輯——app 只讀它拿到的值。`remoteconfig.template.json` 已預先定義兩個條件：

| 條件 | 運算式 |
|---|---|
| `update_rollout_10` | `percent('update_rollout') <= 10` |
| `update_rollout_50` | `percent('update_rollout') <= 50` |

`percent()` 依 Firebase installation ID 分桶，同一台裝置的桶位穩定，不會在批次之間跳進跳出——擴大比例只會納入新的人，不會讓已經看到提醒的人又看不到。

放版流程：
1. 兩邊商店都上架後，把 `update_rollout_10` 的 `latest_version` 設成新版號，`defaultValue` 維持舊版號 → 10% 的人看到提醒。
2. 觀察沒問題，改設 `update_rollout_50` → 50%。
3. 全開時把 `defaultValue` 設成新版號。

灰度**只用在 `latest_version`**。`min_supported_version` 不要掛條件：隨機擋掉一成的人不是灰度，是故障。
