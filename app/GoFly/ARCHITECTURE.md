# GoFly iOS 架構與不變量

## 模組

| 模組 | 職責 |
| --- | --- |
| `GoFlyCore` | 服務、路線、搖桿、漫步、最愛、GPX、恢復與檔案邊界；可在 macOS 測試。 |
| `GoFlyTransport` | VPN 通道探測；端點為 `10.7.0.1` 加上以 Bonjour（`_remotepairing._tcp`，只取本機位址的那筆）自動找到的 remotepairingd 連接埠，不寫死；兩秒期限。失敗時保留 iOS 回報的最後連線狀態（NWError、path 狀態／原因、介面）供 B01 原文顯示；只作診斷。連線被拒絕（ECONNREFUSED）立即判定無法連線，不等兩秒期限。 |
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
   只有 clear 之後才套用閒置 30 秒後在下次操作前重建。瞬移（定點維持的繼續／重試）、路線、搖桿與漫步每次「繼續」（resume）都先在 FIFO 內
   關閉舊 session 並確認通道，繼續後的第一筆寫入在新 session 上送出：App 暫停後在背景被掛起數分鐘時，iOS
   可能已斷開舊連線，沿用它會讓繼續後第一筆寫入失敗而顯示「繼續失敗」（2026-11-02，實機待驗）。已派送的暫時性服務／通道／adapter timeout 錯誤，
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
   **Fly origin（2026-11-17）**：一個 session 的第一筆模擬寫入前，`ServiceController` 記下 `flyOrigin`：優先用 15 秒內的現時真實 GPS，
   否則用系統快取定位（`CLLocationManager.location`，非模擬、最多 10 分鐘舊）。沒有定位授權或兩者都沒有時不記錄。不等待新定位、不延後送點。
   同一 session 後續寫入不覆蓋；以 UserDefaults `GoFly.flyOrigin` 跨 App 重開保存。Stop、Restore GPS 與冷啟動 clear 若有 origin，
   先送一點回 origin、停留約 1.5 秒，再 clear；回 origin 失敗不阻擋 clear。強制 Reset 不回 origin。clear 確認後清除 origin，並沿用既有流程請求真實 GPS；之後的真實定位只把箭頭變藍，不移動鏡頭，鏡頭只在使用者按 Recenter 時移過去（2026-11-23）。
5. watchdog 逾時只回報未知；`repairRequired` 時只允許冪等 Stop。
6. 路線／搖桿／漫步共用一個 writer；路線與道路漫步每 1 秒送一點，手動搖桿（含漫步手動接管）每 0.5 秒（`MovementCadence`），
   步距為速度 × 該間隔，無另外的每步上限；地圖箭頭在路線／漫步前景執行中沿路徑依 ACK 量得的速度預測前進，最多超前一個間隔，新 ACK 於 0.3 秒內修正誤差、暫停或停止時退回最後 ACK；手動搖桿維持兩筆 ACK 之間等速補間（2026-11-17，取代 2026-10-25 的不超前 ACK；僅顯示層，送點不變）。
   道路漫步每步目標是沿路前進一步的點，判定抵達容許 1 cm 誤差；否則浮點誤差會讓約四分之一的步數停在目標前、下一步只移動 0 m，造成箭頭卡頓（2026-11-17 由實機 log 確認：56 步中 15 步為 0 m，已修正、待實機驗證）。
   App 在背景時，路線與道路漫步改為每 2 秒送一點、步距加倍（平均速度與抵達時間不變，寫入次數減半以降低耗電），
   回到前景恢復每 1 秒；步距依該次實際等待的間隔計算，等待中切換前景／背景不會走錯距離。手動搖桿與固定位置心跳不變
   （2026-11-17，程式已改，實機待驗：背景診斷紀錄中路線／漫步寫入間隔約 2 秒、回前景約 1 秒，路線抵達時間與前景一致；省電幅度未量測）。瞬移後的固定位置維持每 15 秒送同一座標作為心跳，
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
   沒有已確認的模擬位置時，Recenter 先把鏡頭移到地圖上現有的位置箭頭（`positionMarker`），再等候真實定位；
   等候期限（`realFixWaitSeconds`）內真實定位抵達後仍會再置中一次。Stop 清除模擬後 iOS 可能持續把定位標為軟體模擬，不能只靠等待真實定位（2026-11-23）。
   定位權限為「大概位置」時，iOS 在模擬清除後仍可能數分鐘回報標為模擬的舊位置（實機 iOS 27.2.1 驗證：開啟精確位置即恢復）。
   因此在 Stop／Recenter 後等候真實定位期間收到模擬定位時，每次啟動最多一次以 purpose key
   `GoFlyRealLocationAfterSimulation` 請求暫時精確位置；同意後立即重新補取（2026-11-23）。
   Stop 的清除以 CoreDevice `com.apple.coredevice.locationservice` 的 `clearsimulatedlocation` 為準
   （與 `devicectl device simulate location clear` 相同）；iOS 27.2.1 上 DVT `stopLocationSimulation` 會回覆成功但不會恢復真實定位，
   仍先送出但結果不決定清除是否成功（2026-11-23，見 `NativeBridge/location-clear.patch`）。
8. 背景由 `GoFlyContinuedProcessingDriver` 管理：Info.plist 宣告 `processing` 背景模式；瞬移維持、路線及漫步共用一個
   `<Bundle ID>.movement` 任務（Bundle ID 依簽署 Team ID 產生）；採 `.queue` 等待系統可用的繼續執行名額。單程路線的目標一律是**整條路線距離**，
   進度＝從目前方向的出發端點（順向為起點、逆向為終點）到目前位置的距離，系統進度條與副標題「路線進度 N%」同值；
   暫停後繼續不改目標也不從 0 重算，切換方向才以新端點重送背景任務（2026-11-17，程式已改，實機待驗；先前是以送出請求當下位置為 0、
   剩餘距離為目標，暫停繼續或切換方向後進度條與文字不一致）。目的地終點 ACK
   呼叫 `finishFiniteArrival` 正常完成；瞬移維持、來回路線及漫步使用 `finiteDuration(43_200)` 的 12 小時百分比，
   進度只累計相鄰有效 ACK 間的單調時間（第一筆為零，超過 15 秒的缺口不計入；瞬移維持為心跳 3 倍的 45 秒）。固定位置 ACK 由其 controller
   提供時間，來回／漫步由 facade 的同 identity／sequence epoch 計時，避免重複計入。達到目標後先完成有效的系統
   任務，再停止維持或暫停移動，不自動接續另一個 12 小時；即使背景 request 未啟動或遭拒，前景 writer 也須到期停止。
   expiry 會暫停移動並在
   回到前景時提示。路線暫停時，Toast 的「繼續」呼叫同一路線的 `resume()`，只在 `route.canResume` 時啟用。切到其他 App
   時，已取得的 continued-processing grant 會保留執行；系統仍可依執行條件（包括資源限制或進度不足）中止。
   `background.taskExpired` 與 `background.progressUnits` 診斷事件可用來核對到期時間與最後回報進度；
   截圖無法單獨判定系統中止原因。
   回到前景時倒數歸零：舊任務以**成功**結束（`setTaskCompleted(success: true)`，不再 `success: false` 加取消），
   再於前景送出全新的背景任務，下次進背景就用新任務、從頭計時；設定中修改背景執行時間也走同一路徑。
   目的是避免每次切換 App 都在靈動島／鎖定畫面留下一張「已停止」的系統提示；iOS 沒有 API 能隱藏或清除任務結束提示，
   成功結束仍可能短暫顯示「已完成」。尚未啟動（仍在排隊）的舊任務只能從排程取消。使用者暫停、取消、連線不可用與到期
   仍以失敗結束（2026-11-17，程式已改，實機待驗：來回切換 App 多次後不應累積「已停止」提示，回背景後移動持續且倒數從頭開始）。
   12 小時是工作上限，並非 iOS 保證的執行時間；不以假進度、重新送背景 request 或冷啟動自動恢復延長系統授權。
9. 冷啟動只還原草稿／顯示位置；上次有 active 或不確定狀態時啟動自動送一次 clear。失敗保持 stopped、
   不設錯誤、不彈窗，只保留 `coldClearPending` 與地圖提示；Start 不受影響。ACK 後清空 session
   的 active／uncertainty 並 flush 成功才解除提示。

## iOS 效能與驗收

- 路段快取先更新記憶體，再由單一寫入者在 MainActor 外編碼與原子寫入。只保留最新待寫快照。跨啟動重用驗收須等該快照落盤，容量仍為 48 段及 4 MiB。
- Session checkpoint 依檔案實際保存的欄位去重。寫入者重用同一 GPX 的編碼結果，位置變更依原有流程保存。驗收核對重複狀態的寫入次數、最新位置與背景 flush 結果。
- 背景呈現依內容變化更新。每筆有效 ACK 照常計入進度，驗收需核對跨授權更新、取消與到期處理。漫步等待下一段時保留原 lease，安裝下一段或狀態變更時喚醒。驗收需涵蓋無計時輪詢、正常接段、取消、斷線與授權失效。
- 地圖節點選取僅重新套用前後節點的樣式。GPX 圓點按原始順序決定同縮放比例的間距，再依可見區略過不相交的點群。驗收需核對選取時路線不重建，以及縮放、平移和切換外觀時的節點及圓點呈現。
- 實機效能待量測。用相同裝置及路線比對主執行緒耗時、寫入次數、接段等待喚醒數與背景系統更新次數。

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
| `RouteLegCache/` | `legs.json`（schemaVersion 1）：已規劃路段（以兩個選定地點為 key）的道路頂點，最多 48 段、4 MiB，超出時丟掉最舊的；讀不到即視為空快取，只省下再次向 Maps 請求，不影響其他資料。UI 測試 fixture 不寫入。 |
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
- 漫步規劃何時恢復由 `WanderPlanningCoordinator` 自己決定：它監聽 service、joystick、recovery 與前景生命週期，在「前景、未檢查連線、連線可用」成立時恢復中斷的規劃，並在成立期間一旦搖桿可接手就啟動已 ACK 的起點；離開前景或連線不可用時放棄未提交的規劃，但一段走完、lease 仍在原地等待下一段時，離開前景不取消該規劃（前景與背景換段都原地等待、不暫停 lease，背景任務不中斷；只有規劃最終失敗才暫停並顯示重試，2026-11-02，實機待驗）；第一筆位置一律立即寫入、不等節奏：瞬移本身就是立即寫入；路線開始時準備階段即寫入起點，路線繼續時先立即重寫已確認的位置（不算抵達端點）；道路漫步開始（瞬移到起點後）與每次繼續時也先立即寫入目前所在位置，讓第一個 ACK 馬上確認任務並申請背景任務；先前要等約 1 秒，這段時間離開 App 會因尚無背景任務而暫停（2026-11-02，實機待驗）；開始漫步遇到 Maps 限流（`RoutePlanningThrottled`）會等待重置時間再試，不立即顯示「無法規劃路線」，且每個開始失敗分支都記錄 `wander.startFailed`（原因：noRoute／originTeleportRefused／joystickRefused／originNotSent）與 `wander.startPlanFailed` 錯誤類型（2026-11-02，實機待驗）；漫步偏離道路或完成一段時自行重新規劃。漫步中手動搖桿接管時，手指經過搖桿中心不算放開：箭頭保持最後方向、原地不動，自動漫步不介入；放開後先規劃從箭頭到原目的地的道路，規劃失敗則直線走回目前路線上最近且尚未走過的點並沿原路線繼續，不顯示「無法規劃路線」（2026-11-01，實機待驗）。coordinator、搖桿起點與瞬移維持的防搶 lease 接線改由 runtime（`GoFlyMovementModel`）建立一次，不再由 view 的 onChange 觸發（2026-11-01）。
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

GoFly 的端點 `10.7.0.1` 是 iOS 的 remotepairingd（連接埠由 iOS 動態指派並以 Bonjour 公告；2026-11-01 實機為 64088，先前記錄的 49152 只是當時的值，每次檢查前重新探索），LocalDevVPN 只把封包繞回手機本機。2026-10-19 實機觀察：iPhone 只用行動網路時，該服務沒有在聽（連線被拒絕，path 經 utun 已滿足）；連上 Wi‑Fi 後服務出現在 49152，檢查才可能成功。因此引導、設定與錯誤文案都要求先連 Wi‑Fi。飛航模式加 Wi‑Fi 但未加入網路、個人熱點，以及使用中途 Wi‑Fi 中斷的行為尚未驗證。

## 路徑取得（2026-10-23）

`FallbackRoutePlanner` 透過 `RoutePathProviding` 依汽車、行人、公共交通順序取得有效道路頂點；Maps 因請求過多回傳 throttled 時，provider 回報 `RoutePlanningThrottled`，該路段不再試其他交通方式，預覽規劃依 Maps 給的時間（沒有則 10 秒）等待後重問同一段，總共最多等 60 秒，期間不顯示錯誤；路段依序一次問一段，規劃好的路段同時存入 `RouteLegCache`，重開 App 時直接沿用（2026-11-01）。「修正順序」的搜尋共用同一份路段快取（記憶體中的預覽結果與 `RouteLegCache`）：先用已規劃的路段，被 throttle 的試探同樣等待後重問，不當成無法規劃；搜尋規劃出的路段存回兩份快取。按「完成」直接採用搜尋得到的路線與路段，不再重新請求。`MapKitRoutePathProvider` 僅負責 MapKit request 與取消，不觸碰裝置。公共交通在 Apple SDK 僅支援 ETA；保留第三順位嘗試，失敗如實回報。此 seam 可供漫步後續共用，目前只接入手動路線。

`PlannedRoute` 以回傳的道路端點執行，不把 POI 座標插入幾何，也不設定 POI-road 距離門檻；保留有限、非零、點數及路段連續性檢查。多段路線從前段實際終點繼續規劃，不能用直線或跳點接不連續路段。編輯草稿仍保留選取地點，預覽另外記住解析後的輸入座標供 Start 重用。編輯與 Retry 透過同一個預覽 Task／revision 取消舊請求並拒絕過期結果；Retry 只取得路徑，不進入裝置準備或移動流程。
