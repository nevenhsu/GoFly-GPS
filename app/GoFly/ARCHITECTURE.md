# GoFly iOS 架構與不變量

## 模組

| 模組 | 職責 |
| --- | --- |
| `GoFlyCore` | 服務、路線、搖桿、漫步、最愛、GPX、恢復與檔案邊界；可在 macOS 測試。 |
| `GoFlyTransport` | VPN 通道探測；唯一正式端點 `10.7.0.1:49152`、兩秒期限。失敗時保留 iOS 回報的最後連線狀態（NWError、path 狀態／原因、介面）供 B01 原文顯示；只作診斷。連線被拒絕（ECONNREFUSED）立即判定無法連線，不等兩秒期限。 |
| `GoFly` App | SwiftUI 與 `GoFlyRuntimeAssembly`；只建立一份 runtime owner。 |
| `Device`／`NativeBridge` | 單一 serial session、固定 idevice 來源、窄幅 patch 與 allowlist header。 |

## 命令與送點

1. `ServiceController` 是唯一裝置命令 owner；Start／Stop／Restore／Reset／瞬移／路線／搖桿共用私有 FIFO，
   上一筆原生呼叫實際返回後才執行下一筆。
2. `PointDispatchGate` 是最後派送門檻；native adapter 真正送點前同步 `claim()`。已 dispatched 的呼叫
   不能被取消或 Stop 假裝撤回。
   Teleport、路線與搖桿／漫步共用同一個 native session owner。`DeviceSessionKeeper`（GoFlyCore）決定
   session 重用、閒置關閉與寫入失敗後是否關閉 session；每筆寫入只嘗試一次，不自行重試；`NativeDeviceService`
   也只做單次嘗試。裝置可能仍有模擬位置時（任何已派送的寫入之後，直到 clear ACK），session 不因閒置關閉；
   只有 clear 之後才套用閒置 30 秒後在下次操作前重建。已派送的暫時性服務／通道／adapter timeout 錯誤，
   由 `ConnectionRecoveryController` 決定自動重連：只在同 lease、執行中、未停止且仍具前景或有效背景授權時，
   經 `ServiceController.repairConnection` 在 FIFO 內重建 session 並重新確認同一絕對座標。同一任務內自動重連
   每 60 秒最多一次（ADR 0001；2026-11-01 程式補上此間隔，先前成功後立即重置）；使用者明確重試不計入並重新
   計時。自動重連失敗，或 60 秒內再次中斷時，任務停下並顯示連線中斷，等使用者按「重試」。
   任務執行中探測失敗只更新連線狀態，不暫停任務，由下一筆寫入決定是否重連。原始不確定結果
   只有真實恢復 ACK 才可解除；失敗、身分／配對錯誤及外層 watchdog 到期仍走原本未知／Stop 流程。
   連線檢查不定時輪詢：只在回到前景、網路路徑變化（唯一的 `GoFlyPathMonitor`）、未知／中斷狀態的後續狀態
   變化（最多每 5 秒一次）及使用者檢查時探測；已可連線時不再探測。任務中以 ACK 證明存活。
3. 位置只在核對過的 ACK 後更新；`unconfirmed` 保留候選並鎖住 Go，直到明確 Stop 完成。
   箭頭另有僅供顯示的驗證狀態：失去通道、背景 runtime 或無有效 runtime 離開前景時保留最後座標、轉為灰色等待。
   前景恢復、TCP 探測成功與 prepare 不會恢復箭頭，新的定位 ACK 才可恢復；有效背景 runtime 中的 ACK 同樣有效。
   此狀態不修改 movement lease／health 或既有 ACK 座標，也不提供原生 session 持續健康的保證。
4. Stop 先撤銷舊結果發布權，再排入唯一一筆 clear；clear 必須等已 claim 呼叫返回。
   設定頁的「停止」呼叫 `stop()`（結束移動＋clear＋關閉 session），不再呼叫只結束移動的 `stopSimulation()`（2026-10-25）。
5. watchdog 逾時只回報未知；`repairRequired` 時只允許冪等 Stop。
6. 路線／搖桿／漫步共用一個 writer；路線與道路漫步每 1 秒送一點，手動搖桿（含漫步手動接管）每 0.5 秒（`MovementCadence`），
   步距為速度 × 該間隔，無另外的每步上限；地圖箭頭在兩筆 ACK 之間以等速補間，不超前 ACK（2026-10-25）。瞬移後的固定位置維持每 15 秒送同一座標作為心跳，
   網路路徑變化時立即補送一次（2026-10-25）。沒有 writer 的保留狀態（路線／漫步暫停、手動搖桿放開）由
   `PositionKeepAlive` 在前景每 15 秒經同一 FIFO 重送同一座標；keepalive gate 只在同 lease、健康、執行或暫停且具前景
   或有效授權時派送，不改 lease、run state 或顯示位置。取消路線、取消漫步或搖桿結束後，若裝置仍有未清除的
   模擬位置，`PositionHoldController` 以新 lease 接手成為瞬移維持；Stop／Restore 排定 clear 後不接手。
   `PositionHoldController` 只接受新瞬移的真實 ACK，並在 async 開始前核對原點位、lease 與顯示／admission epoch。
   固定位置 intent 與 recipe 互相限制，不能用方向移動或朝目標靠近；新的使用者操作會先撤回舊維持任務。
   所有原生命令仍共用同一 FIFO，遲到 ACK 不得復活舊 lease。
7. `MovementTaskAuthority` 以 lease／snapshot 同步比較健康與執行狀態；背景 dispatch 需有效 grant。
   真實定位不需高精度：`GoFlyRealLocation` 以百公尺精度（`kCLLocationAccuracyHundredMeters`）單次 `requestLocation()`
   取得，不持續 `startUpdatingLocation()`。`RealLocationRefresher` 只在前景每 8 秒補取一次，使搖桿與路線起點所需的
   「15 秒內真實定位」維持有效；收到軟體模擬的定位（裝置正被模擬）即停止補取，直到 Recenter、建立搖桿起點、
   GPS clear 確認或回到前景時重新嘗試（2026-10-26）。`observeRealLocation` 只在路線或搖桿起點的可用性改變
   （含過期定位被新定位取代）或該筆定位讓已派送的瞬移進入 sending 時，才送 `availabilityChanged`；
   只是更新已可用起點的定位不喚醒 route／joystick 的觀察者（2026-10-26）。
8. 背景由 `GoFlyContinuedProcessingDriver` 管理：Info.plist 宣告 `processing` 背景模式；瞬移維持、路線及漫步共用一個
   `<Bundle ID>.movement` 任務（Bundle ID 依簽署 Team ID 產生）；採 `.queue` 等待系統可用的繼續執行名額。單程路線回報 ACK 距離比例，目的地終點 ACK
   呼叫 `finishFiniteArrival` 正常完成；瞬移維持、來回路線及漫步使用 `finiteDuration(43_200)` 的 12 小時百分比，
   進度只累計相鄰有效 ACK 間的單調時間（第一筆為零，超過 15 秒的缺口不計入；瞬移維持為心跳 3 倍的 45 秒）。固定位置 ACK 由其 controller
   提供時間，來回／漫步由 facade 的同 identity／sequence epoch 計時，避免重複計入。達到目標後先完成有效的系統
   任務，再停止維持或暫停移動，不自動接續另一個 12 小時；即使背景 request 未啟動或遭拒，前景 writer 也須到期停止。
   expiry 會暫停移動並在
   回到前景時提示。路線暫停時，Toast 的「繼續」呼叫同一路線的 `resume()`，只在 `route.canResume` 時啟用。切到其他 App
   時，已取得的 continued-processing grant 會保留執行；系統仍可依執行條件（包括資源限制或進度不足）中止。
   `background.taskExpired` 與 `background.progressUnits` 診斷事件可用來核對到期時間與最後回報進度；
   截圖無法單獨判定系統中止原因。
   12 小時是工作上限，並非 iOS 保證的執行時間；不以假進度、重新送背景 request 或冷啟動自動恢復延長系統授權。
9. 冷啟動只還原草稿／顯示位置；上次有 active 或不確定狀態時啟動自動送一次 clear。失敗保持 stopped、
   不設錯誤、不彈窗，只保留 `coldClearPending` 與地圖提示；Start 不受影響。ACK 後清空 session
   的 active／uncertainty 並 flush 成功才解除提示。

## 首次啟動與 setup 身分

1. 沒有 `incoming.json`、`readback-request.json` 或 activation 時直接一般啟動，不讀身分。
2. `LocalGoSetupHandoff` 在讀取或匯入舊式 pairing envelope 前，先將 `incoming.plist` 原子 rename 為 `incoming.plist.consuming`；Mac restart 與 iOS 消費者競爭同一來源路徑，確保只有一方認領。失敗後留下的 consuming claim 會在下一次 App 啟動時繼續處理，Mac 看到 claim 時不會刪除或封存其交易。
3. activation 與 input 的啟動比對只綁 bundle ID；build、profile、executable 雜湊不參與啟動阻擋。
   重建、覆蓋安裝與 `renew` 會改變雜湊，但不會把 App 鎖在 `identityMismatch`。
4. Mac readback 握手仍綁完整身分（bundleID、build、兩個 SHA-256）。只有這條流程會計算
   profile 與執行檔（上限 256 MiB）的雜湊；一般啟動不計算。

## 儲存

資料位於 `Library/Application Support`：

| 目錄 | 格式 |
| --- | --- |
| `GoFlySetup/` | setup 交接與 activation；不屬本機存檔重構。 |
| `FavoritePlaces/` | `favorites.json`（schemaVersion 1）。 |
| `ImportedRoutes/` | `manifest.json` 索引＋`<uuid>.gpx` payload。 |
| `FavoriteRoutes/` | `manifest.json` 索引＋`<uuid>.route` payload。 |
| `SessionRecovery/` | `session.json`（schemaVersion 1）。 |
| `Diagnostics/` | `gofly.jsonl`：JSONL ring，上限 2 MiB，超出時在行邊界保留最新一半。 |

`AtomicFile` 是唯一讀寫 primitive：no-follow、大小上限、`.atomic` 寫入、0700／0600、
`completeUntilFirstUserAuthentication`。路線新增先寫 payload 再換 manifest；刪除先換 manifest 再刪 payload，
失敗只忽略；不做目錄掃描或 orphan cleanup。manifest 有但 payload 缺失的項目標為不可用，不自動移除。
損壞或未知 schema 會封鎖後續寫入，不覆寫原檔；檔案不存在視為空資料，不先建立目錄。
匯入路線／最愛路線復原只在 store 記憶體保留最近一次刪除的 record＋payload，重啟後不可復原。

2026-10-20 UI 改版所需的最小 Core 增補：
- `FavoritePlacesStore.delete(Set<FavoritePlaceKey>)` 將選取項目合為一次原子持久化；`undoDelete()` 一次恢復最近一批的地點、標籤與原順序，重複存在的地點不新增副本。只保留最近一批的記憶體復原，不改 favorites schema。清單星號的 0.5 秒等待與取消屬 UI，取消不寫資料。
- 新 GPX 匯入保留實際讀入的原始 bytes，manifest 記其大小與 SHA-256。選取與匯出核對 payload 大小、digest 及解析結果；匯出分享核對過的儲存 payload，不重新編碼。舊版已正規化儲存的 payload 繼續可讀，先前丟失的原始 metadata 無法還原；沒有 schema migration。

## UI 呈現邊界

- 地圖 view 的最近搜尋僅記憶體保存最多 8 筆，隨 view 生命週期結束而消失；不改 SessionRecovery 或偏好格式。
- 全螢幕搜尋的路線結果點選只回填原節點；點圖最小避讓及跟隨方向只操作 camera，不建立送點命令。
- 「目前的移動」（`ActiveMovement`，GoFlyCore）是唯一判斷「裝置上正在跑或停在哪一件移動、為何暫停、能否繼續」的地方：依序看路線、搖桿／漫步、瞬移維持，與目前分頁無關。狀態 pill、恢復提示、`isResumeState` 與背景阻擋診斷都讀它；分頁只由 view 用 `kind` 再過濾。瞬移維持暫停時記錄原因（連線或背景），不再一律視為使用者暫停（2026-11-01）。
- 前景生命週期（`SceneLifecycle`，GoFlyCore）是前景狀態進入 Core 的唯一入口：地圖畫面只回報 scenePhase，真實定位、繼續執行與 keepalive 在活動狀態改變時各收到一次（重複回報不重跑）。檢查點擷取、連線前景檢查與 1 秒 UI 穩定計時仍在 view；繼續執行對 recovery／瞬移維持的轉發依其 lease 判斷，留在 `MovementContinuationController`（2026-11-01）。
- 地圖上方有哪些浮動提示、誰壓過誰，由 `MapNoticeBoard`（GoFlyCore）依領域狀態算出有序清單；地圖 view 只渲染並接上動作。規則：靜默修復進行中或可重試時，只顯示連線提示（不再顯示服務錯誤或恢復提示）；瞬移分頁的未確認點位提示壓過服務、準備失敗、連線與恢復提示；使用者自己暫停的路線或漫步不顯示恢復提示；恢復提示等前景穩定 1 秒後才出現。Status pill 仍由 `SessionStatusErrors` 判斷，因為關閉提示不清除錯誤；設定頁的兩個提示維持各自邏輯（2026-11-01）。
- 漫步規劃何時恢復由 `WanderPlanningCoordinator` 自己決定：它監聽 service、joystick、recovery 與前景生命週期，在「前景、未檢查連線、連線可用」成立時恢復中斷的規劃，並在成立期間一旦搖桿可接手就啟動已 ACK 的起點；離開前景或連線不可用時放棄未提交的規劃；漫步偏離道路或完成一段時自行重新規劃。漫步中手動搖桿接管時，手指經過搖桿中心不算放開：箭頭保持最後方向、原地不動，自動漫步不介入；放開後先規劃從箭頭到原目的地的道路，規劃失敗則直線走回目前路線上最近且尚未走過的點並沿原路線繼續，不顯示「無法規劃路線」（2026-11-01，實機待驗）。coordinator、搖桿起點與瞬移維持的防搶 lease 接線改由 runtime（`GoFlyMovementModel`）建立一次，不再由 view 的 onChange 觸發（2026-11-01）。
- 路線／漫步進行與暫停使用執行模式。路線結束沿用取消路線；漫步結束呼叫 `setWanderEnabled(false)`，沿用取消漫步、保留最後模擬位置；設定的 Stop／Restore 仍是清除定位入口。
- 啟動先以 Logo 銜接既有 detached setup check，500ms 後才顯示進度；沒有提前建立第二份 runtime。
- 首次引導與設定共用 `GoFlyVPNHelpPage`、`GoFlyExternalLinks`；URL 依 LocalDevVPN、App Store 順序嘗試，全部失敗才提示手動搜尋。權限只請求 When In Use，不新增背景定位模式。
- UI 改版不改上述命令與送點不變量，#15 箭頭方向與移動停止根因修復不屬本輪。實作與驗證分開記錄於 `work/gofly-ios/redesign/RESULT.md`。

## 診斷

1. 所有診斷同時送 `os.Logger`（subsystem `com.neven.gofly`，category 為 `movement`、`device`、
   `background`、`tunnel`）與 `Diagnostics/gofly.jsonl`。關鍵事件（phase 轉換、watchdog、session
   建立／關閉／重用、FFI 失敗、背景 submit／launch／expire、通道探測、路徑變化、scene 變化）用
   `.notice` 以上；每個 tick 的細節用 `.debug`，只留在 App 內檔案。
2. 每個 tick 記序號、每個 FFI 呼叫的名稱與耗時、結果；失敗只記數字 `code`／`subcode` 與對應的
   `DeviceServiceFailure`。**不記 FFI message**（可能含配對資料、裝置 ID、路徑）。
3. 座標最多三位小數；不記裝置識別碼、配對內容。檔案權限 0700／0600，沿用 `AtomicFile` 重寫。
4. 匯出在「設定 › 裝置與簽名」；只產生暫存分享檔，不改動 ring。

## VPN 通道需要 Wi‑Fi

GoFly 的端點 `10.7.0.1:49152` 是 iOS 的 remotepairingd，LocalDevVPN 只把封包繞回手機本機。2026-10-19 實機觀察：iPhone 只用行動網路時，該服務沒有在聽（連線被拒絕，path 經 utun 已滿足）；連上 Wi‑Fi 後服務出現在 49152，檢查才可能成功。因此引導、設定與錯誤文案都要求先連 Wi‑Fi。飛航模式加 Wi‑Fi 但未加入網路、個人熱點，以及使用中途 Wi‑Fi 中斷的行為尚未驗證。

## 路徑取得（2026-10-23）

`FallbackRoutePlanner` 透過 `RoutePathProviding` 依汽車、行人、公共交通順序取得有效道路頂點；`MapKitRoutePathProvider` 僅負責 MapKit request 與取消，不觸碰裝置。公共交通在 Apple SDK 僅支援 ETA；保留第三順位嘗試，失敗如實回報。此 seam 可供漫步後續共用，目前只接入手動路線。

`PlannedRoute` 以回傳的道路端點執行，不把 POI 座標插入幾何，也不設定 POI-road 距離門檻；保留有限、非零、點數及路段連續性檢查。多段路線從前段實際終點繼續規劃，不能用直線或跳點接不連續路段。編輯草稿仍保留選取地點，預覽另外記住解析後的輸入座標供 Start 重用。編輯與 Retry 透過同一個預覽 Task／revision 取消舊請求並拒絕過期結果；Retry 只取得路徑，不進入裝置準備或移動流程。
