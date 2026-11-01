# Route Mode 開發任務清單（2026-10-26）

視覺準據：Figma `04 · iOS Redesign（Google Maps 參考）`，`D · 路線：規劃、選點、執行模式`（D1–D23、D6.a 與 Dark 對應）。所有 UI 依 Light／Dark 渲染畫面比對，並使用 `0 · 共用元件（正式版 token）`。
行為與元件規格：[iOS UI 設計與驗收規格](IOS-UI-DESIGN.md)，其中「2026-10-24 共用元件規格」一節列出數值。
本文件只列待辦與證據，不代表已實作或已通過真機驗證。程式路徑相對於 `app/GoFly/`。

## 已確認決定

- 進入路線 tab：D1 完整面板，不自動開 D5／鍵盤。起點預設目前位置，無最後模擬位置與真實 GPS 時留空。
- 預設選中「起點」（依 Figma D1）。路線地點欄位第一次點擊選取欄位；再次點擊同一欄位開啟 D5 並聚焦搜尋輸入。點另一欄位會先選取該欄位，再次點擊才開啟 D5。頂部搜尋列仍可直接開啟 D5；地圖 Pin（D4）也回填目前選中欄位。
- 自動收合只由候選 Pin 觸發，拖曳地圖不收合。
- 起點與終點常駐 ✕（空值時停用），清除後保留空欄位；停靠點 ✕ 刪除整列；皆不顯示 toast／snackbar（2026-10-26 使用者指示，取代 D9 可復原 snackbar；Figma D9 未同步）。
- 路線與搖桿／漫步共用並保存同一速度偏好：5／25／50／100，預設 25。
- D1 不顯示速度膠囊；只有 D1 右上星號開 D19，底部星號開 D20；undo 文案「復原」。
- D1 路線面板移除反轉按鈕，改為 Figma `View List Icon: list.and.chevron` 自訂向量、無外框的「檢視路線」（英文 View）。點擊推入 D23「全部地點」左滑全螢幕導覽頁：共用返回／置中標題列，單一 card 內以序號、地點、角色顯示每列；不放拖曳 grip 或刪除圖示；下方保留「＋ 新增停靠點」與「⇅ 反轉順序」。D23 已有 Light／Dark 設計並於票 14 實作；D13 GPX 點位頁僅作為交互規格參照，不是 D23 的視覺來源。
- D1b（Pin「新增」為目的地）已廢止。

## 共用元件（先做，路線頁面依賴）

| # | Figma 元件 | App 現況 | 待辦與驗收 |
| :-- | :-- | :-- | :-- |
| C1 | `Toast / 系統訊息 / danger｜warn｜success` | 兩套實作：`App/GoFlyStatusBanner.swift`，與 `App/GoFlyWarningToast.swift`（14／12 pt 字、實心 `#FF9500` 邊、固定 80 pt、寫死「重試」） | 合併為單一 tone 驅動元件：15 pt Semibold／13 pt Regular、圓角 14、內距 12／14、邊框 35% 不透明、白色 56 × 32 膠囊動作、20 pt ✕、高度隨內容。驗收：D8（danger＋重試）、D10（warn＋重試）、D18 渲染對齊；深色對齊 Dark D8／D10；最大字級可換行。<br>**狀態：已實作，待審查**（2026-10-24 補：B10「需要連接 Wi-Fi」改為 danger＋「重試」、說明文字依渲染畫面，行高 21／18 對齊，`GoFlyWiFiToastUITests`；B10 說明文字寫「無動作按鈕」，與渲染畫面的「重試」衝突，依渲染畫面；「重試」＝重新讀取 Wi-Fi 狀態，Figma 未定義其他行為）（`GoFlyWarningToast` 已移除，D10 改用 `GoFlyStatusBanner(tone: .warning)`；`GoFlyToastUITests`）。 |
| C2 | `Snackbar / 2 秒自動消失`、`Snackbar / 可復原` | `App/GoFlySnackbar.swift`：`.footnote` 字、純文字 action、時長固定 2 秒（modifier 可傳 duration）、陰影 18%／12 | white 15 pt Medium、24 pt 綠勾、內距 10／14、雙層陰影；action 改白色 56 × 32 膠囊，右側共用 X 關閉按鈕（44 × 44 命中區）；Toast 與 action／X 相鄰間距統一 8 pt；Dark 所有 Toast 說明小字與 X 同用 primary 色。可復原版本 5 秒；可指定位置（D22 位於底部搜尋區上方 12 pt）。驗收：B6、D9、D17、D22 對齊；地點卡複製 snackbar 與卡上緣 8 pt，瞬移收合面板位置複製 snackbar 與 panel 上緣 8 pt（2026-10-30 使用者確認，Figma／App 已同步）。<br>**狀態：已實作，待審查**（含 action 的 snackbar 預設 5 秒、其餘 2 秒；位置仍由 `bottomPadding` 決定，D9／D22 位置隨 R4 處理；`GoFlySnackbarUITests`）。 |
| C3 | `StatusPill / 啟動｜模擬中｜暫停｜停止｜連線中斷` | `App/GoFlyStatusPill.swift` 版型相符（2026-10-25 已改圓點色 `tone.pillDot`＝`#8E8E93`／綠／`#FF9F0A`／紅，深色底 `#3A3A3C`；待審查） | 回歸：點色 `#8E8E93`／`#34C759`／`#FF9F0A`／`#8E8E93`／`#FF3B30`、雙層陰影。D6 顯示「模擬中」、D10「暫停」、D6.a 開啟時「停止」。文案依「三模式 session pill 五態規格」。 |
| C4 | `SearchBar / 浮動`、`SearchField / focused｜normal`、Slider、Progress | 搜尋列已存在；DESIGN.md 舊規則用 `systemGray5` 輸入底 | SearchField 改 `#F2F2F7` 底、focused 1.5 pt `#007AFF`、normal 0.75 pt `#8E8E93`。路線選中列沿用 focused 樣式。Progress 6 pt、Slider 黑白軌道。驗收：D5、D1 選中列、D6 進度列、D7 slider 對齊。<br>**狀態：已實作，待審查**（`goFlySearchField(isFocused:)`、`GoFlyProgressStyle` 已套用；D1 選中列隨 R3 套用；`GoFlyFieldUITests`）。 |
| C5 | checkbox（圓形）on／off | `GoFlyCheckboxIcon`（2026-10-25 已改：on 24 pt、off 22 pt 1.5 pt `#C7C7CC` 框、深色 `#2C2C2E` 底＋`#8E8E93` 框；待審查）（`GoFlyFavoritesView.swift:176`、`GoFlyFavoriteRoutesView.swift:156`） | 回歸：on 24 pt 黑圓白勾（深色白圓黑勾），off 22 pt `#C7C7CC` 1.5 pt 邊（深色 `#2C2C2E` 底＋`#8E8E93` 邊），44 pt 命中。驗收：C3、D21 淺深色。 |
| C6 | `TabBar / 瞬移・路線・搖桿（等寬）` | `App/GoFlyBottomBar.swift`：圖示 22 pt、`caption2` bold／medium | 圖示 25 pt、選中 2.29 pt 黑線＋10 pt 黑字、未選 1.875 pt `#999999`；背景 `#F9F9F9` 96%＋頂部細線；高 83 pt（含 home indicator）。驗收：D1–D4、D8、D9 的 `Mode=路線` variant 對齊；執行模式（D6／D7／D10）隱藏。<br>**狀態：已實作，待審查**（`GoFlyTabBarUITests`：高 83、三格等寬、選中 trait）。 |

| C7 | 地圖右下角 `Recenter`（Figma 已同步修正為單一按鈕） | `App/GoFlyMapView.swift:1246` `mapControls` 有三顆：執行模式「跟隨方向」、地圖旋轉後「指北」、「回到定位」；位置以 `sheetHeight`＋bottom bar 計算；`GoFlyMapCanvas.swift:117／125` 殘留未使用的 `MKCompassButton` | 所有 mode 只保留「回到定位」，點擊同時重設正北；移除跟隨方向、指北與殘留 compass 程式碼與字串。按鈕固定在當下 panel 上緣上方 16 pt、右側 16 pt。驗收：B1、B2、D1、D2、D3、D6、D10、E1、E2 截圖量測間距皆 16 pt；拖曳 sheet 時按鈕跟隨；地點卡、D5、D6.a、D7 開啟時隱藏；UI test 確認 `map.followHeading`、`map.north` 不存在。<br>**狀態：已實作，待審查**（`GoFlyMapControlsUITests` 量測瞬移／路線／搖桿與收合；按鈕在地點卡、搜尋、選點時隱藏；點擊同時轉正北。未涵蓋：執行／中斷面板與 dialog 隱藏，隨 R6／R7 驗證）。 |

## 路線頁面

### R1 共用速度偏好（D7）
- 現況：`App/GoFlySpeedSheet.swift:10` 為 `[5, 20, 60, 120]`；`Sources/GoFlyCore/RouteDraft.swift:17` 預設 20；路線（`RouteDraft.speed`）與搖桿（`JoystickMovementController.speed`、`SessionRecoveryStore.joystickSpeed`）各自保存。
- Figma D7：40% dim、標題「設定移動速度」＋右上「完成」、「目前時速 25 km/h」、4 膠囊（選中黑底白字）、Slider 1–120、底部「完成設定」。
- 做法：快選改 5／25／50／100、預設 25；在 `GoFlyPreferences` 新增單一移動速度偏好，路線與搖桿共用；保留 session 復原但以偏好為初始值。
- 驗收：首次安裝兩處皆 25；D7 改 50 後漫步顯示 50，反之亦然；重開 App 保留；執行中改速即時更新 D6 剩餘時間；單元測試涵蓋共用與保存。
- **狀態：已實作，待審查。** `RouteSpeed.standard` 改 25、`RouteSpeed.presets` 為 5／25／50／100；新增 Core `MovementSpeedSynchronizer`（路線 draft 與搖桿／漫步速度雙向同步，忙碌中的一方於 phase 變化後補同步）與 `GoFlyPreferences.movementSpeed` 持久化；`MovementSpeedSynchronizerTests`、`GoFlySpeedUITests`。`SessionRecoveryStore.joystickSpeed` 仍保存，但啟動初始值改取偏好。舊預設 20 的兩處單元測試期望值（`JoystickModelTests`、`RouteModelsTests`、`JoystickMovementControllerTests`）依新預設 25 更新。「執行中改速即時更新 D6 剩餘時間」待 R6 的 D6 面板驗證。

### R2 起訖空值與 D1／D2 清單（D1、D2）
- 現況：`RouteNodeValue` 無空值；`RouteDraft()` 只建立起點；`App/GoFlyRouteNodeList.swift:134` 只對停靠點顯示刪除。
- Figma D1／D2：清單卡 353 pt、圓角 14、0.5 pt 邊；每列 60 pt，左 grip、角色小標 12 pt（起點／停靠點 N／終點）、地點 17 pt；右側中性灰 ✕（44 pt）。
- 做法：起點與終點為固定欄位、可為空值；端點 ✕ 常駐、空值時停用；停靠點 ✕ 刪除整列；角色名稱統一「停靠點 N」。
- 驗收：任一端點為空時 Start 停用且不規劃；反轉順序同時交換空值；GPX 唯讀不顯示 ✕；VoiceOver 區分「清除起點」「刪除停靠點 N」。
- **狀態：已實作，待審查。** Core 新增 `RouteNodeValue.empty`、預設 draft 為〔目前位置、空〕、`removeNode` 對端點改為清除（停靠點仍刪列）、`hasEmptyEndpoint` 阻止規劃與 Start；recovery codec 支援 `empty` 並把舊的單節點快照補成空終點。UI：端點 ✕ 常駐（空值停用）、停靠點 ✕ 刪列、占位列移除、角色名稱統一「停靠點 N」（zh-Hant／zh-Hans／en 同步）。`RouteEndpointTests`、`GoFlyRouteEndpointUITests`。Figma 衝突：D8 的停靠點列畫紅色垃圾桶，D2 與已確認決定為中性灰 ✕，依後者實作。D1 列卡片樣式（353 pt、圓角 14）與 grip 顏色隨 R5。

### R3 選中欄位與再次點擊搜尋（D1、D4、D5）
- 現況：頂部搜尋列已直接開 D5；點擊清單列只選取欄位。
- Figma：D1 Route list 外卡 Light 用 `color/canvas`、Dark 用 `color/surface/control`；選中列 Light `surface/card`、Dark `surface/control/active`，加 1.5 pt primary 邊線與選中 trait，圓角與清單外卡一致（14 pt）。新增停靠點文字／加號使用 `color/text/accent`。D5 搜尋欄為空時顯示「使用目前位置」與「最近搜尋」；輸入文字後顯示搜尋結果。D5 Favorite 使用無底色 Ghost Icon + Text inline button（星號＋繁中／簡中「最愛／最爱 Favorite」、英文「Favorite」），命中區至少 44 pt；Role chip 上下留 16 pt、使用目前位置列下方留 16 pt、搜尋清單列上下留 8 pt。
- 做法：維持選中欄位狀態與 D1 樣式；第一次點欄位選取，第二次點同一欄位透過 `openSelectedPicker()` 開 D5 並聚焦搜尋欄；點其他欄位會選取並重新開始兩次點擊流程。路線頂部搜尋列仍可立即開 D5；D4 Pin 與 LocationCard 的「確認」仍回填選中欄位並返回 D1。
- 驗收：進入路線 tab 不彈出 D5 或鍵盤；第一次點任一欄位不開 sheet，第二次點同一欄位開 D5 且 chip／placeholder 顯示該欄位；第一次改點其他欄位只更新選中狀態；返回不改原值；選取結果只改選中欄位；選中狀態不只靠顏色（`.isSelected` trait）；`Favorite` 入口使用無底色 Ghost Icon + Text、依介面語系顯示「最愛／最爱 Favorite」或 `Favorite`，命中區至少 44 pt 且 VoiceOver 名稱對應目前語系；點空欄位不顯示 toast。
- **狀態：App 已實作，未實機驗證。** Core 沿用 `RouteExecutionController.selectedNodeID`、`selectNode`、`openSelectedPicker`、`confirmSelectedNode(with:)`。App 以待確認欄位 ID 區分第一／第二次點擊，第二次開 D5 並聚焦；移除空欄位提示 toast 及其字串。D5 最愛入口使用無底色 Ghost Icon + Text inline button（22 pt 空心星號、中文「最愛／最爱 Favorite」、英文 `Favorite`、44 pt 以上命中區），VoiceOver 名稱沿用 `favorites.shortTitle`。Role chip 視覺上下間距 16 pt、使用目前位置列下方間距 16 pt、搜尋清單列上下間距 8 pt；「使用目前位置」列改用與最近搜尋相同的 list row 排版，置於 card 色圓角卡片且不再加圓形 icon tile。D1 focused row 的 1.5 pt primary 邊線使用與清單外卡相同的 14 pt 圓角。Figma D1 維持目前選中列渲染，D5 已同步 focused 搜尋頁與 Primary 星號＋`Favorite` 入口；靜態 Figma 未定義再次點擊互動 variant，本次同步畫面與規格。

### R4 D9 清除復原
- 現況：`removeNode` 無復原。
- Figma D9：C2 `Snackbar / 可復原`「已清空路線地點」＋「復原」，位於 bottom sheet 上方約 12 pt。
- 驗收：5 秒內復原原值與原位置；逾時消失；連續刪除只復原最近一次；三語；深色 Dark D9。
- **2026-10-26 取代：** 使用者指示清空或刪除路線地點不顯示 success toast；App 已移除「已清空路線地點」＋「復原」snackbar 與 `route.removed` 字串，`GoFlyRouteUndoUITests` 改驗證清除後沒有 snackbar。Core 的 `undoRemoval()` 保留但 App 不再呼叫。驗收：清除起點／終點、刪除停靠點後畫面沒有任何 toast／snackbar。尚未實機驗證。
- 原狀態（已取代）：Core：`removeNode` 記錄 `(before, after, selection)`，`canUndoRemoval`／`undoRemoval()`（只復原最近一次；之後路線有任何其他變動即失效）；App：起訖清除與停靠點刪除皆顯示「已清空路線地點」＋「復原」（5 秒，於 sheet 上方 12 pt，已修正 snackbar 位置多算 safe area 的偏移）。`RouteEndpointTests`（undo 三項）、`GoFlyRouteUndoUITests`。訊息文字依 D9 渲染畫面統一為「已清空路線地點」（停靠點刪除與起訖清除相同）。

### R5 D1／D2 面板版面
- 現況：`GoFlyRoutePanel.editingView` 顯示標題、清單、新增與「檢視路線」入口；底部收藏為 56 pt 共用 icon button。
- Figma：D1 Route list 外卡 Light 使用 `color/canvas`（`#EEEEF3`），Dark 使用 `color/surface/control`（`#2C2C2F`）；選中列 Light `surface/card`、Dark `surface/control/active`，搭配 1.5 pt primary 邊線。標題 20 pt Semibold；右上 44 pt 圓鈕；「＋ 新增停靠點」文字與加號採 `color/text/accent`；「檢視路線」配 22 pt route-list icon。底部收藏按鈕為 56×56 pt、star icon 28 pt：Light `surface/control/floating`（解析為 `#FBFBFD`）＋`line/border`；Dark `surface/card`＋`line/separator`；接著為 56 pt「開始」capsule。D2 多停靠點畫面保留「⇅ 反轉順序」；清單捲動（最多 4 列可視、顯示捲動指示器），其餘固定。
- 驗收：Light／Dark D1 均顯示「檢視路線」與 `list.and.chevron`，D2 保留「反轉順序」；D1、D2 截圖並排對齊；5 個以上地點時捲動清單不拖動 sheet；最大字級時可重排。
- **狀態：已實作，待本票 Light／Dark 截圖驗證。** 路線規劃 sheet 依內容定高（`sheetFitsContent`、`grabberHeight: 12`）。D1 header 距 sheet 頂 12、清單距 header 12、2 列各 60 pt、新增／檢視路線列距清單 4 pt、收藏／開始列距操作列 16 pt、sheet 距 TabBar 20 pt；D3 收合 96 pt。清單卡 14 圓角、0.5 pt 邊、最多 4 列後捲動；其餘區塊固定。D2 Figma 四列容器高度與 D1 列高、底部間距不一致；App 保持共用 60 pt row，僅清單可捲動。新截圖驗證以票 09 執行紀錄為準。

### R5.1 D23 全螢幕「全部地點」路線清單
- 入口：D1「檢視路線」推入左滑全螢幕導覽頁，使用共用返回／置中標題列；返回按鈕與原生向右返回手勢可退出。
- 版面：canvas 背景；標題「全部地點」；左右 16 pt 單一卡片，列內顯示序號、地點名稱與起點／停靠點 N／終點角色，最小列高 46 pt，末列不加分隔線；無拖曳 grip 或刪除圖示；卡片下方留 12 pt 後放「＋ 新增停靠點」與「⇅ 反轉順序」（垂直反轉圖示 `GoFlyIconAsset.swapVertical`）。
- 行為：點列沿用 App 的欄位選取／再次點擊開 D5；新增仍在最後建立空終點並捲至新列，反轉仍使用同一份 route draft。這些互動是既有 App 行為，Figma 沒有 prototype 規格。最大 Dynamic Type 時文字換行且列高增長、footer 垂直排列，於 ScrollView 內可捲動不裁切。
- **狀態：App 已按 D23 渲染重整；Light／Dark fixture 截圖與差異記錄見票 14 執行紀錄。未做實機驗證。**

### R5.2 GPX 匯入與匯出（D11–D18）
- D11 已匯入路線是全螢幕導覽頁；點選路線顯示 D12 action card（40% 遮罩、card 底、四列操作與取消），檢視全部點位以 D13 推入唯讀全螢幕頁，不使用 dragger sheet。
- D13 共用導覽列為左返回、置中標題；檔名與點數資訊列下方右側顯示小字「唯讀」，不放在導覽列。點位列用 16 pt 左右內縮分隔線、card 底、`Theme/subheadline` 座標文字並顯示 5 位小數，序號用 `Theme/footnote`。D15 長路線以起點、第 2 點、中間點數、終點及「查看全部」摘要；編號欄需容納千位數，點位與已匯入清單分隔線左右各內縮 16 pt。
- D14 與 D16 使用系統分享與檔案選擇器。D11／D17／D18 底部匯入按鈕下緣距 sheet 底部 40 pt；D17 成功提示改為帶 X 的 Snackbar，不提供「載入」action，與匯入按鈕間距 16 pt；D18 失敗 StatusBanner 懸浮於 header 下方，保留重試及 X 關閉，不推動內容。
- 匯入資料模型目前只保存檔名、起訖座標與點數，無具名端點或路線距離；Figma 樣例的具名端點／距離不會由 UI 假造。系統分享與檔案選擇器視覺以運行中的 iOS 系統為準，與 Figma 靜態圖可能不同。
- **狀態：App 實作與 Light／Dark 模擬器截圖驗證見票 13 執行紀錄；未做實機驗證。**

### R6 D6／D6.a 執行面板與結束確認
- 現況：`App/GoFlyRoutePanel.swift:81` 使用系統 `confirmationDialog`，文案「取消這次路線？」。
- Figma D6：頂部深色指示卡（導航箭頭、「前往 …」、剩餘距離／時間／速度）、`StatusPill / 模擬中`、右側 Follow／Recenter、底部進度列（`Progress`）、純圖示控制列（來回、方向、速度 chip「⏱ 25 ›」）、「✕ 結束」（灰 capsule）＋「⏸ 暫停」（黑 capsule）。
- Figma D6.a：35% 遮罩、居中 dialog（圓角 20），標題「結束這次路線？」，說明「確認後將停止模擬路線並保留目前位置，回到路線規劃模式。」，灰色「取消」與紅色「結束路線」並排 capsule；pill 顯示「停止」。
- 驗收：取消後路線繼續、進度不變；結束後停止送點、保留最後模擬位置並回 D1；dialog 開啟時其他元素不可操作、VoiceOver 焦點鎖定；Dark D6.a 對齊；三語。
- **狀態：已實作，待審查。** `GoFlyEndRouteDialog`（35% scrim 吞掉觸控、`.isModal`、取消／結束路線 capsule 48 pt）取代 `confirmationDialog`，由 `GoFlyMapView` 疊在整個畫面；`GoFlyRouteRunningControls`（標籤列 6 pt 進度 → 20 → 36 pt 控制列 → 20 → 56 pt 結束／暫停）；執行模式加 pill、面板加 grabber；dialog 開啟時 pill 顯示「停止」。`GoFlyRouteExecutionUITests` 以 gallery 量測間距與 dialog；因模擬器無法實際執行路線，pill 顯示「停止」、真實面板內的結束流程未做 UI 自動驗證。

### R6.1 移除 D1b「新增」
- 現況：`App/GoFlyMapView.swift:680` 與 `:1415` 呼叫 `route.appendDestination`（`RouteExecutionController.swift:160`）。
- 做法：與 R3 一起處理；路線 Pin 與 LocationCard 只保留「確認」（D4：Pin 上 28 pt 黑底「確認」、卡片「確認／收藏／複製」）；移除未使用的 append API、字串與 UI test。
- 驗收：路線 tab 點 Pin 不出現「新增」；選中停靠點時確認只改該停靠點。
- **狀態：已實作，待審查。** 已移除 `appendDestination`／`RouteDraft.appendingDestination`、`LocationCardPrimaryAction.add`、`common.add` 字串與未使用的 `useCandidateInRoute`；`map.route.addCard` 改為 `map.route.confirmCard`。

### R7 D10 / D10.a 中斷與暫停恢復
- 2026-10-25 / 2026-10-26 使用者確認與 Figma 拆分：
  - **D10 · 路線中斷 / 恢復（系統中斷）**：只有系統異常暫停／中斷時（`suspensionReason` 非空或 `interrupted`）才顯示 C1 warn toast（「路線模擬已暫停」＋中斷說明＋「繼續」＋✕；說明文字仍提到「重試」是 Figma caption 與畫面渲染差異，依渲染使用「繼續」）；使用標準執行控制面板（進度列、來回／方向／時速控制列、結束＋play 圖示「繼續」）。
  - **D10.a · 路線中斷 / 恢復（使用者暫停）**：路線進行中由使用者主動按暫停時之畫面，無 warn toast；相對 D6 只換 StatusPill（暫停）、頂部卡文字與暫停圖示、主按鈕（play 圖示＋「繼續」），使用標準執行控制面板。
- Figma D10／D10.a Light／Dark：頂部卡顯示暫停圖示＋「已暫停 · 前往 …」及 `StatusPill / 暫停`；四個面板均為 229 pt 標準執行面板，包含進度列、來回／方向／時速控制列與結束＋藍色「繼續」按鈕（play glyph）；不使用 76 pt 窄面板。D10 有獨立 warn toast，D10.a 無 toast；均無 TabBar。這是 2026-10-27 Figma 設計更新，取代舊的 76 pt 面板描述。
- 驗收：淺深色（D10、D10.a、Dark D10、Dark D10.a）結構、229 pt 面板與控制列 1:1 對齊；只有 D10 顯示 warn toast；「重試」與「繼續」呼叫同一 resume；toast 關閉不影響面板。Play icon 向量座標（4.96, 2.83）與 disabled 狀態（D1 等）外框描邊色彩與填色一致（淺色 `#8E8E93`、深色 `#98989F`）。設計更新只同步 Figma 與規格，App panel 目前仍按 `GoFlyResumePanel` 既有 122 pt 路線恢復版面記錄，尚未因本次 Figma 修改而實作或裝置驗證。
- **狀態：已實作，待審查；Figma 版面仍待 App 對齊。** 頂部卡標題改「前往 X」／暫停時「已暫停 · 前往 X」（Pause 圖示原已有）；pill「暫停」（R6 已在執行模式顯示 pill）；warn toast 文案改 D10（「路線模擬已暫停」＋「任務意外中斷，點選重試自中斷點恢復行進。」＋「重試」＋✕，`route.resume`）；`GoFlyResumePanel` 已有副標（「路線已暫停 · 45%」／「剩餘 1.2 km · 預估 14 分鐘」）與「繼續路線」按鈕，D10 content height 為 88 pt（面板另受 34 pt safe area 影響），E5 為 76 pt，無 TabBar。`GoFlyRoutePausedUITests` 以 gallery 驗證文案與 76 pt 狀態；實際暫停流程（含頂部卡、pill、關閉 toast 不影響面板）因模擬器無法執行路線，未做 UI 自動驗證。2026-10-27 Figma 已更新為 229 pt 標準控制面板，App 尚未依此靜態設計變更實作或裝置驗證。頂部卡的 5 km/h 以實際偏好值顯示（依「待決與 Figma 衝突」）。

### R8 回歸
- 收合：拖曳／縮放地圖不改變面板高度；放 Pin 收合為 76 pt（D3：只剩標題與兩個圓鈕）；確認或關閉 Pin 卡回 D1。
- 最近搜尋：`App/GoFlyMapView.swift:194` `recentPlaces` 已共用；D5「清空記錄」後瞬移也清空，仍只存在記憶體、最多 8 筆。
- D19／D20 入口、D1 無速度膠囊、D22 黑底「復原」維持正確。
- **狀態：已實作，待審查。** `GoFlyRouteCollapseUITests`（拖曳地圖不改 panel、Pin 收合 76 pt、關閉卡片回 D1）、D22／D21 由 `GoFlyFavoriteRoutesPageUITests` 驗證；最近搜尋共用同一份記憶體清單（`recentPlaces`，最多 8 筆、清空同步）以程式檢視確認，未另寫 UI test。2026-10-25 全部 UI test 回歸：除 `GoFlyOnboardingUITests.testSkipLocationRequiresReachableVPNAndBackKeepsFlow`（在改版前的基準版即失敗，VPN 不可達時「下一步」仍可點，原因未查）外皆通過；搖桿 UI test 在 `766c748` 即失敗（模擬器無裝置，Start／Go 皆停用，且從搖桿 tab 搜尋會被切到瞬移 tab），已修正 tab 行為並把測試改成模擬器可驗證的斷言；`GoFlyRedesignScreenshots` 已移除依賴已刪控制項（`placeDetails.go`）的舊截圖流程。已知未處理：瞬移地點卡下緣比 TabBar 上緣低約 37 pt，會蓋住 TabBar 的一部分。

## 最愛清單版面與 tab 行為（2026-10-24 追加）

本節最初記錄 2026-10-24 的 D19–D22 工作基線；其「D21／D22 是可拖曳 sheet」等描述已被 Figma 04 新渲染與票 14 取代。現行 D19–D23 視覺與驗收以本文 R5.1、上方 D13 說明及票 14 執行紀錄為準。

| # | 項目 | 現況 | 待辦與驗收 |
| :-- | :-- | :-- | :-- |
| F1 | 最愛路線清單是整頁，不是 dragger sheet | `GoFlyRoutePanel` 以 `.sheet` 開 `GoFlyFavoriteRoutesView`，並設 `presentationDetents`／`presentationDragIndicator`；地點版 `GoFlyFavoritesView` 同樣設定 | 路線版改 `fullScreenCover`，兩頁移除 detents／drag indicator／presentationBackground；返回鍵文字依 D19 為「路線」；列為 64 pt（36 pt 星號圓、17 pt 標題、13 pt 單行副標＝起訖・點位數）；底部搜尋區 122 pt（頂部 1 pt 分隔線、欄位 361 × 48、上 12／下 28＋安全區），欄位與 D20 標籤欄同用 `goFlySearchField`。D20 仍是 sheet。 |
| F2 | 多選刪除鍵移出搜尋區 | 刪除鍵在 `bottomSearch` 內，與搜尋欄同一背景 | 刪除鍵移到搜尋區上方、獨立於搜尋區背景：361 × 48 紅色 capsule，距搜尋區頂 12 pt（D21：y 670–718、搜尋區 y 730）。最愛地點頁比照。D22 復原 snackbar 位置同為搜尋區上方 12 pt。 |
| F3 | 點 tab 還原最小高度的 panel | `selectMode` 只對非瞬移 tab 強制 `.expanded`，瞬移 tab 不還原 | 點瞬移／路線／搖桿任一 tab，若目前 panel 為最小高度（收合），還原到可見高度（瞬移最多可見 4 個地點；路線、搖桿為內容高度）；非最小高度時不變。 |

狀態：F3 已實作，待審查（`selectMode` 在最小高度時還原；`GoFlyTabRestoreUITests`）；F1、F2 已實作，待審查（最愛路線、最愛地點兩頁改整頁、移除 detents／drag indicator；新增共用 `GoFlyFavoritesBottomBar`＝搜尋區 88 pt＋刪除鍵在其上方 12 pt、snackbar 偏移 100 pt；`GoFlyActionStyle(fixedHeight:)`；`GoFlyFavoriteRoutesPageUITests` 量測 D19／D21／D22 間距；地點頁共用同一元件，未另寫 UI test）。路線列副標改單行「起訖・點位數」，D19 的距離（12.4 km）因紀錄沒有距離資料未顯示。R6 的程式已由使用者另行提交（`385a5ed`），其 UI test 在「dialog 開啟時下方按鈕不可操作」斷言上失敗，原因未釐清，仍待處理；R7、C3、C5、R8 仍待做。

## 三個 mode panel 的預設與最小高度（2026-10-25；2026-10-27 Figma 對齊更新）

高度以 TabBar 上緣以上的可視點數計（無 TabBar 的執行畫面計到螢幕底，含 34 pt 安全區）。

| Mode | 預設高度（Figma） | 最小高度（Figma） | 實作 |
| :-- | :-- | :-- | :-- |
| 瞬移 | 300（B2 半開 298） | 120（B1 收合 118） | `sheetPreferredHeight`；B8/B9 沿用標準瞬移收合面板與位置摘要 |
| 路線 | 340（D1 339，2 列）；3 列 400；上限 416（D2 414，只有清單捲動） | 76（D3） | 內容定高（`GoFlyRoutePanel`），清單上限＝404 − 208 |
| 搖桿 | 352（E1 350：列 20、搖桿 88×152、按鈕 264×52、距底 36） | 76（E1.a：標題「搖桿」＋時速 chip） | `GoFlyJoystickPanel` 重排，`isCollapsed` 為最小態 |
| 執行／恢復（路線／漫步） | D6 229；D10／D10.a 229；E5 76 | — | App `GoFlyResumePanel` 現有 D10 122（88＋34）／E5 76；Figma D6、D10／D10.a 已更新為 229 pt，App 尚未依本次靜態設計變更調整或裝置驗證 |

狀態：已實作，待審查（`GoFlyBottomSheet.preferredHeight`／`grabberHeight`；輔助字級與恢復態改回內容定高；`GoFlyPanelHeightUITests` 量測三個 mode 的預設／最小高度與搖桿內部間距）。尚未對齊：漫步執行 E2（380）、E2.a／E4（122，皆無 TabBar；App 仍顯示 TabBar）、搖桿標題字級（E1 約 17 pt，現為 20 pt）。D2 的列高（55 pt）與 D1（60 pt）不一致，依 60 pt 並以 414 pt 為上限。

## 追加修正（2026-10-25）

- **VPN 不可達不可下一步：** `GoFlyVPNOnboardingView` 的「下一步」原本在檢查未通過時仍呼叫 `onComplete()`（繞過），已移除；按鈕在 `canAdvanceVPN`（檢查成功）前停用。`GoFlyOnboardingUITests.testSkipLocationRequiresReachableVPNAndBackKeepsFlow` 驗證。
- **路線／漫步模擬中沒有 TabBar：** 路線執行原本即隱藏；漫步執行中（非暫停）現在也隱藏（`isWanderRunning`，暫停的 E5 仍保留 tabs），並顯示頂部導航卡＋pill；E2 面板 380／E2.a 與 E4 為 122（量到螢幕底），E4 地點卡距底 28 pt。因模擬器無法實際漫步，這部分只有建置與靜態對照，未做 UI 自動驗證。
- **Toast：** 「尚未允許 GPS 定位」warning toast 移除；「連線無法使用」改 error（danger）toast、按鈕「重試」（共用 `recovery.checkConnection`；冷啟動待確認時為「恢復」）；有按鈕的 toast／snackbar 中文按鈕不超過 2 字（設定、重試、復原、載入、恢復、說明），英文單字；`EnglishButtonLabelTests` 檢查，`GoFlyConnectionToastUITests` 驗證。

## 間距統一（2026-10-25）

Figma 的間距沒有精修（如 23、17、35、14），實作統一到 4 pt 格：容器內距與間距取最接近的 4 的倍數，剛好在中間的（如 10、14、18、22）往上取；≤1 的線寬不動，2–3 取 4。已套用於地圖、面板、toast、snackbar、卡片、清單與 dialog（不含設定、首次引導、VPN 說明、GPX 頁與圖示幾何）。結果：toast 內距 16／間距 12、icon 24；snackbar 內距 16／12、高 56；面板底距 35→36；執行面板頂距 22→24；進度標籤間距 6→8；dialog 內距 21→20；搖桿圓盤 150→152；瞬移 118／298→120／300；路線上限 414→416。所有面板標題統一 `GoFlyStyle.panelTitleFont`（20 pt Semibold）；「連線無法使用」toast 改短文案（「連線無法使用」＋「請確認 Wi-Fi 與 VPN 後重試。」，恢復成功的 toast 不帶說明與按鈕）。UI test 的數字已改為格線值。

## 建議順序

C1–C2（R4、R7、D8 依賴）→ C4、C6、C7 → R1 → R2 → R3＋R6.1 → R5 → R4 → R6 → R7 → C3、C5、R8 回歸。R2、R3、R5 都改路線面板，應在同一分支依序處理。每項需單元測試或 UI test；最後依 `docs/AI-INSTALL.md` 安裝到實機，以淺色與深色截圖對照 Figma 驗收。

## 待決與 Figma 衝突

- 預設選中起點時，第一次點 Pin 確認會取代「目前位置」起點；要設定目的地須先點終點列。這是依 Figma D1／D4 的行為，若希望第一次 Pin 直接設目的地，需改設計。
- D1 選中列帶藍色游標，看起來像可直接輸入；目前規格視為選中狀態標示，不在列內開鍵盤。
- D1 說明文字仍寫「點欄位開 D5」、D9 說明寫「搜尋列下方」與「還原」、section 說明寫「D1 右上或下方星號開 D19」，皆與渲染畫面或已確認決定不符；以渲染畫面與決定為準，說明文字待更新。
- D6／D6.a／D10 頂部卡寫「5 km/h」、Speed chip 為「9」，與 D7 預設 25 不一致；實作顯示實際偏好值。
- `StatusPill / 連線中斷` 元件實際文字為「錯誤」；`Toast / warn` 元件預設按鈕「繼續」，D10 覆寫為「重試」。


## 2026-10-26 路線 UI 更新（Figma 04 · iOS Redesign，待裝置驗證）
- 搜尋 sheet：「使用目前位置」對起點、停靠點、終點皆顯示；目前位置只能有一列，選到新列時舊列被清空（起訖）或刪除（停靠點）。
- 「新增停靠點」：在清單最後新增空欄位並選取，使其成為新終點；原終點保留原值並降為最後一個停靠點，不開搜尋 sheet（`addEmptyWaypoint`）。面板與全部點位頁新增後都捲至新欄位。
- 編輯中路線規劃結果變更時，地圖自動縮放平移以框住整條路線。
- 新增最愛路線 sheet：儲存鈕緊接資訊卡下方 24 pt，不再固定於 sheet 底部。
- D10／D10.a：暫停或中斷皆沿用執行面板；僅系統中斷顯示 warn toast，使用者暫停不顯示。
- D10 系統中斷主按鈕顯示「繼續」（play icon），沿用連線修復後自中斷點恢復；D10.a 使用者暫停同樣顯示「繼續」，不顯示 warn toast。
- 規劃前自動合併連續重複地點（`mergingConsecutiveDuplicates`，保留第一個、不取代終點）；合併後不足兩點仍為 invalidPath。列表不變，只影響規劃與執行用的路線。
- 路線模式地圖新增 `FitRoute` 按鈕（`map.fitRoute`，位於 Recenter 上方 12 pt，有規劃路線時顯示）。Figma 尚無此 variant，待設計補上；與「地圖只有一個 Recenter」的舊規範衝突，以此使用者指示為準。

## 2026-10-30 D8 規劃失敗自動修正（App 實作）

- Figma D8 Light／Dark 的規劃失敗 banner 顯示 danger 樣式與「修正」／`Fix` action。按下後重排所有點位（含原起點）並重新規劃；成功採用新順序及預覽，失敗保留草稿與錯誤 banner。連線錯誤仍使用「重試」／`Retry`。
- 搜尋最多 27 個點位與 4,096 個排序前綴，不設單次請求上限（每個有向地點對最多請求一次並快取）；目前預覽已完成的路徑段會重用。使用者編輯會取消當次搜尋，舊結果不得覆蓋新草稿。搜尋只更新路線草稿與地圖預覽，不發送移動命令。
- App 與三語文案已同步；核心測試覆蓋 2／3／27 個點位、替代順序成功、全序失敗及中途編輯取消。D8 UI test 與 Light／Dark 截圖路徑記於 `.scratch/gofly-ios-figma04/issues/11-route-fix-order-on-plan-failure.md`。未做實機驗證。

## 2026-10-30 Figma 04 追加 UI 規則（最新）

- D5 Favorite 為無底色 Ghost icon＋文字按鈕；中文介面顯示「最愛 Favorite」／「最爱 Favorite」，英文顯示 `Favorite`。搜尋列至 Role/Favorite 列為 12 pt，該列至「使用目前位置」16 pt，位置列至最近搜尋標題16 pt，最近搜尋標題至首列8 pt。
- D8 規劃錯誤屬非連線錯誤時，Start 保持可操作並可重新規劃；端點無效、連線／裝置 admission 不可用時仍停用。Start 不以 `plannedRoute != nil` 或殘留錯誤旗標作為唯一可用性條件。
- D10 中斷面板 action 標示「繼續」並使用 play 圖示；仍執行原有連線修復／同一路線恢復。D10.a 使用者暫停亦為「繼續」，不顯示 warn toast。
- D19–D22 導覽列選取 action 改為「選取」文字按鈕，顏色依 Primary/C1；D23 路線卡片至 footer 按鈕間距 12 pt。
- D6、D7、D10、D10.a、D11、D17、D18、D20、E2、E3 的底部主要按鈕至所屬 panel／sheet 底部留 40 pt。D11／D17／D18 的 GPX 匯入 CTA 依此量測；D17 成功 Snackbar 為 16 pt 高於 CTA。
- App／Figma 變更不改路線規劃或命令、送點、ACK、安全准入語意。Figma 為靜態 wireframe，無 prototype wiring；本輪 `check.sh` 尚待重跑，未做實機驗證。
