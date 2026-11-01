# GoFly iOS UI 設計與驗收規格

> [!IMPORTANT]
> **主要設計稿唯一準據（Visual Authority）**
> - **iOS UI 主要設計稿唯一準據**：Figma 頁面 **`04 · iOS Redesign（Google Maps 參考）`**（node-id: `121-50359`）。
>   連結：https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359
> - 所有畫面配置、元件、圖示、色彩語意、邊距尺寸與狀態反饋，**一律以 04 頁面的渲染畫面為最終準據**。
> - 舊版 `01 · iOS App`（`13-2098`）與過往舊線框已全面廢棄，嚴禁引用。
> - 若本文件任何文字規格與 04 頁面渲染畫面產生歧異，無條件以 04 畫面為準，並同步更新規格。

確認日期：2026-10-18。使用者要求把線框細化後直接實作於 iOS App，**不修改 Figma**。這句記錄當時的工作範圍；後續確認的視覺來源與差異以本文件「Google Maps 參考改版」及「Figma 對照紀錄」為準。中文使用 **iOS 內建系統字體**。本文件補充 `DESIGN.md`，流程與命令語意仍依原開發規格；不增加頁面、權限或新的送點操作。

## 視覺系統

App 顏色使用 Figma 04 Theme Variables 的完整語意 token，由 `GoFlyThemeColor` 對應；`GoFlyStyle` 與 `GoFlyTextColor` 只提供元件角色別名。Light／Dark 值與 Common Color 原值保存於 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json) 的 `colors.figmaVariables`，舊 `colors.primitive`／`colors.themes` 是先前色票整理結構，不作為 Swift token 來源。主要動作使用 Figma Primary；Dark primary 按鈕文字與圖示使用純白，依 2026-10-29 使用者決定覆寫 Dark `color/action/primary/text` 的近白值。狀態色仍需搭配圖示與文字，不可單靠顏色辨識。

| 角色 | 設計與實作 |
| --- | --- |
| 字體 | App 文字使用 [`IOS-TYPOGRAPHY.md`](IOS-TYPOGRAPHY.md) 的 `GoFlyFont` 語意 token；中文使用 iOS 系統字體。Figma 04 的 `Theme/<token>` 是共用字型、字級與字重樣式，文字顏色另綁 Light／Dark theme 變數；不以 Figma 樣式推定 App 已同步實作 |
| 面板標題 | 路線 `.title3.bold`；狀態 `.headline`；一般內容 `.body`；說明 `.subheadline`／`.footnote` |
| Sheet 標題 | 背景運行時間、新增最愛路線、編輯最愛（地點／路線）、設定移動時速四個 sheet 不顯示標題，僅保留左右操作按鈕與拖曳指示（2026-10-26 使用者指示） |
| 底面 | `color/canvas`；卡片／Sheet `color/surface/card`；控制底 `color/surface/control`；停用面 `color/surface/disabled`；浮動控制使用 `color/surface/control/floating` |
| 邊界 | 主面板 20 pt 連續圓角、`color/line/separator` 0.5 pt 分隔線；搜尋／地點 14 pt；資料列及較小卡 12 pt |
| 輸入區 | 搜尋／標籤欄位使用 `color/surface/input`、`color/line/input/default`；聚焦使用 `color/icon/accent`。只有 UIKit 系統輸入／貼上控制保留原生色彩行為 |
| 層次 | 一般頁面卡平面。地圖浮層只用 Figma 04 的陰影 token（`GoFlyShadow`，淺深色相同）：`floating`＝9% y5 blur24＋6% y1 blur3（搜尋列、面板、snackbar 等）；`toast`＝18% y4 blur16（Toast／Banner）；`card`＝14% y8 blur24（地點卡）；`chip`＝6% y1 blur4（時速 chip、36 pt 純 icon 鈕）。對話框、搖桿握柄、Pin 另依各自 Figma 元件 |
| 主要按鈕 | 17 pt 語意 body semibold，最低內容高 44 pt，加上下各 6 pt；可因換行長高。僅地圖候選 Go 在無障礙字級取消額外上下留白，保留自然字高與至少 44 pt 操作範圍，避免鍵盤壓縮可視地圖 |
| 次要按鈕 | 同主按鈕字級，最低內容高 44 pt，加上下各 2 pt、柔灰底與細邊界 |
| 語意色彩 | `GoFlyThemeColor` 一對一對應 Figma Variable path；深色階梯 canvas／card／control／active 分別為 `#0B0B0D`／`#1A1A1C`／`#2C2C2F`／`#48484D`，淺色階梯為 `#EEEEF3`／`#FBFBFD`／`#DEDEE4`／`#B9B9BF` |
| 圖示按鈕 | 最小 44 × 44 pt，圓形灰底；啟用圖示用主要色、停用圖示用 disabled 灰，停用底與啟用底使用不同灰階，停用時移除邊線。共用圖示隨字級有限度縮放至最大 24 pt，避免極大字級溢出圓形；設定圖示依容器使用 18–24 pt。標籤與目前可用狀態由原有 accessibility 說明提供 |
| 留白 | 主面板內距 16 pt；頁面／詳情可用 24 pt；分組 20–24 pt；相關元素 8–12 pt |
| 按壓 | 按鈕即時降低亮度／透明度；不移動點擊範圍、不以動畫拖延命令 |

`GoFlyStyle` 是元件共用角色來源；`goFlyCard(floating:radius:)` 統一卡片，`GoFlyEmptyState` 統一空白狀態。平台控制（導航、選單、滑桿、鍵盤、授權及確認框）保留原生互動行為。背景與卡片使用語意底色，地圖內容不會透入文字區。

## 畫面與狀態細節

| 畫面／區域 | 實作細節與保留規則 |
| --- | --- |
| 首次歡迎／定位權限 | Logo 啟動銜接歡迎頁；背景檢查超過約 0.5 秒才顯示細進度條。引導顯示 1／2／3 步驟；定位頁 Light／Dark 都不顯示導航返回列，R02／R03 使用 120 pt Hero、28 pt `Theme/display` 標題與 15 pt `Theme/subheadline` 說明（R02 標題框 x=16、y=348、361×39 pt；說明框 x=53、y=400、287×42 pt）。定位區分尚未設定、已允許與已拒絕，主要動作分別為允許定位、下一步、前往設定；已允許不顯示略過，其餘可略過。App 使用 `Font.system` token；Figma 畫面中的填色 `icon/location` 尚未出現在共用 Icon 板，App 暫用既有 `icon/nav` 資產並記錄差異。R07 說明不含「安裝 App 後」；R06 目前沒有 Figma frame |
| VPN 引導／說明 | R04 使用 canvas 背景、card 步驟清單（Wi‑Fi／開啟 LocalDevVPN／點 Connect／點重新檢查）、連線說明連結、中間 StatusPill 與單一底部 Primary CTA。VPN 檢查失敗時錯誤 Banner 由共用 Toast overlay 懸浮，不推動內容；檢查成功後自動再次確認並進入 B1 收合 sheet，不顯示 success Toast。R05 使用自訂返回列、三列步驟卡（下載／開啟 LocalDevVPN／點 Connect）及一張 troubleshooting 卡；沒有大標題、副標、底部 CTA 或本機網路權限列。R05 返回會重新檢查 VPN；前兩步仍保留 App Store 與 LocalDevVPN deep link fallback |
| 地圖頂部 | 浮動搜尋列由兩張獨立浮動卡片組成（x: 16 pt，總寬 361 pt）：左側為縮短的搜尋輸入卡（301 × 50 pt，包含搜尋放大鏡、query 與貼上／清除圖示），右側為獨立的設定按鈕卡（50 × 50 pt，包含齒輪圖示）；下方狀態 pill；執行模式與全螢幕頁隱藏一般 chrome，頂部不放啟停 |
| 模式列 | 底部瞬移／路線／搖桿三個等寬 tab（TabBar / 瞬移・路線・搖桿（等寬））；最愛由內容入口開啟。執行模式與全螢幕頁隱藏 bottom bar。選中模式無 filled color，僅純線框 line 變深（strokeWeight 2.29 pt、#000000 / #E5E5EA，文字 Medium 10 pt 加深），未選中維持 1.88 pt 細線與次要灰（#999999 / #8E8E93），完全對齊 B1 地圖首頁樣式 |
| 搜尋 | 地圖首頁與全螢幕搜尋輸入欄在空 query 時顯示 44 pt 命中範圍的純 SF Symbol `doc.on.clipboard` 貼上圖示，無底色；首頁使用 20 pt 圖示，Light 為中度灰 `#6B6B6B`、Dark 使用 `#E5E5EA`，保持可辨識且不呈現 disabled 感。首頁 SearchBar / 浮動整體 361 × 50 pt：輸入卡 301 × 50 pt，右側另有獨立設定卡 50 × 50 pt，兩卡間距 10 pt；設定圖示採 Figma `Settings / 設定` 元件內 `icon / gear` 向量（22 pt），輸入框與 Settings 內層按鈕均採 14 pt 圓角與 1 pt 邊（Light Settings 白底／`#C7C7CC`；Dark Settings `#4C4C4F` 底／`#636366` 邊）；兩側 wrapper 各自保留雙層浮動陰影。輸入有文字時隱藏貼上並只顯示清除 ✕。貼上動作使用 iOS 系統 `UIPasteControl`（icon-only、capsule，由系統繪製剪貼簿圖示，前景色為上述灰／白、底色同欄位），query 為空時才可見。`UIPasteControl` 是安全控制：不得以透明度、隱藏或覆蓋自繪圖示偽裝，否則系統會忽略點擊（2026-10-26 修正：舊實作 alpha 0.01＋自繪圖示導致首頁貼上無反應）。首頁貼上的接收端直接讀取 `NSItemProvider` 文字並 trim，不經隱藏輸入欄。貼上來源為純文字時，在插入前移除該字串頭尾空白與換行（`.whitespacesAndNewlines`）；手動輸入及既有文字不額外 trim。首頁貼上後立即確認搜尋，不呼叫 `beginSearch` 或開啟全螢幕搜尋頁；有效經緯度立即建立候選地點卡，名稱則比對最愛標籤、名稱與地址，否則以 MapKit 搜尋後自動選取首筆結果。無效經緯度顯示「無效經緯度」warning toast，沒有搜尋結果顯示「找不到位置」，搜尋失敗顯示「搜尋失敗」；toast 約 2 秒自動消失，沒有 action 或關閉按鈕，以上錯誤皆不得建立候選或 location card。全螢幕輸入頁貼上只依目前文字游標／選取範圍插入並即時搜尋，保持該頁開啟。非純文字剪貼簿不貼入。系統控制避免程式直接讀取剪貼簿造成額外授權提示。驗收：剪貼簿值 `  25.03123, 121.55150\n` 貼入後 query 為 `25.03123, 121.55150` 並立即顯示候選地點卡；首頁貼上後 `showingSearch` 不變；無效經緯度、無搜尋結果及搜尋失敗只顯示對應無按鈕 toast 且不顯示 location card；輸入頁按貼上後文字及搜尋結果更新、該頁仍開啟且游標可繼續輸入；空 query 僅有無底色的 SF 貼上圖示，有文字時僅有清除按鈕。名稱搜尋將原始輸入交由 MapKit 搜尋，以目前可視地圖區域作搜尋提示、不改寫查詢文字；直接輸入有效座標。搜尋中 spinner 與「搜尋中…」同列不折行。空輸入搜尋頁顯示「最近搜尋」（右側「清空記錄」純文字按鈕；依 2026-10-23 Figma B3 移除最愛地點區塊）；沒有最近搜尋時頁面留白，不得顯示「找不到地點」空狀態（只在已輸入查詢且無結果時顯示）。路線選點全螢幕頁（D5）頂部 chip 顯示「選擇終點」／「選擇途經點 %ld」／「選擇起點」，同行最右側為 22 pt 空心星號搭配文字 `Favorite`（15 pt Medium），按鈕高度 44 pt；圖示與文字使用主文字色（Light `#000000`、Dark `#E5E5EA`），VoiceOver 名稱為 `Favorite`，點擊開啟最愛清單；「最近搜尋」同行配置「清空記錄」。選點清單不顯示「從地圖上選擇」（改由 D1 / D1.a 地圖直接釘選）。最近搜尋只在目前地圖 view 生命週期的記憶體保留，最多 8 筆；瞬移搜尋與 D5 共用同一份歷史，任一處清空會同步清空，D5 最愛與瞬移共用 `FavoritePlacesStore` |
| 地點選項 | 無框結果列呈現標題與地址／座標，最愛標籤優先；點列返回地點 sheet 或回填指定路線欄位，不直接送點 |
| 路線規劃 / Pin 設定選中的路線地點（D1.a） | 由 D1 路線規劃模式直接在地圖上移動放置大頭針或點選任意地點（正式取代原 D2a「從地圖上選擇」）；Pin 上方浮動「確認」黑底膠囊按鈕（承襲小 Go 樣式，高 28 pt，圓角 14 pt，純文字「確認」，無任何圖示，44 pt 觸控命中）；釘選時下方同步浮現地點 card（顯示名稱、地址與座標），Figma 卡片 CTA 顯示共用 Light Go（App 尚未同步）；底層維持「高度最窄 panel UI」（僅呈現「規劃路線」與星號、資料夾圖示），完全釋放地圖視覺；點擊 Pin 上的「確認」或 App 對應的卡片 CTA 後，設定／回填該座標至目前選中的路線地點欄位（起點或終點），並返回 D1 展開面板 |
| 路線地點欄位選取與搜尋 | 第一次點擊起點、停靠點或終點欄位時選取該欄位；再次點擊同一欄位開啟 D5 全螢幕搜尋並聚焦輸入。改點另一欄位會先選取新欄位，再次點擊才開啟 D5。路線頂部搜尋列維持直接開啟 D5；空欄位點擊不顯示提示 toast。Figma D1 的選中列與 D5 搜尋頁渲染沿用，不代表 Figma 已定義此點擊互動；目前缺少對應 prototype／互動 variant |
| 路線清單檢視（D23，2026-10-30 依 Figma 渲染更新） | D1「檢視路線」推入左滑全螢幕導覽頁；標題列使用共用返回／置中標題元件。D23 卡片左右 16 pt、角色與順序列最小 46 pt，顯示序號、地點名稱與起點／停靠點 N／終點；使用 card 底與 separator 線，不顯示拖曳 grip 或刪除圖示。卡片下方保留「＋ 新增停靠點」與「⇅ 反轉順序」。點列沿用 App 既有選取欄位／再次點擊開 D5 行為；該互動是 App 行為，不代表 Figma 已定義 prototype。最大 Dynamic Type 可換行並增高列，頁面仍可捲動。
| 點地圖 Pin 直接新增目的地（D1b，已廢止） | 2026-10-24 使用者確認廢止：04 頁無 D1b frame，且與「選中欄位」模型重複。路線規劃模式下點地圖 Pin 一律走 D4：Pin 上方只有「確認」，回填目前選中的欄位（預設選中起點，要設定目的地須先點選終點列）。不再提供「新增」膠囊或「附加為目的地」動作 |
| 位置箭頭／候選 Go／Pin | 位置箭頭區分真實位置與模擬位置：RealArrow 與 SimArrow 均採 22×22 pt frame，箭頭輪廓與 24 pt `icon/nav` 等比例縮放至 22 pt 後一致；RealArrow 保留實心藍色（iOS systemBlue `#007AFF`）、`#E5E5EA` 外框與微陰影，不使用空心；SimArrow Light 採黑色填色、白色描邊，Dark 採 `#E5E5EA` 填色、黑色描邊，不使用綠色或紅色；SimArrow 等待／未確認時維持相同黑白配色並以 50% opacity 呈現。兩者皆無圓底／外圈。路線與漫步執行時依實際模擬行進方位即時計算切線角度旋轉（來回路線逆向時自動旋轉 180° 對齊起點方向），維持箭頭方位與行進路線一致。候選 Pin 上方小型 Go 約 28 pt，命中至少 44 pt；地點 sheet 亦有同一 Go，未確認位置時兩處停用 |
| 地點詳情 | 地點詳情 sheet 與瞬移／搖桿／漫步候選卡共用 `GoFlyLocationCard`（361 × 180 pt、圓角 16 pt、無邊框、95% `surface/overlay/location-card` fill、12 pt 背景模糊與 Figma 浮層陰影）；B5 渲染中的卡片主按鈕為「Start／開始」，候選 Pin 的標籤仍是 Go；卡片與瞬移收合面板「目前位置」摘要共用 `GoFlyLocationTitle` helper，標題依序選有效最愛標籤、地名、地址、經緯度（空白標籤視為沒有標籤）。摘要仍為面板列，不代表共用整張地點卡（2026-10-26 使用者指示）。驗收：空白標籤後使用地名；沒有地名時使用地址；都沒有時顯示經緯度。地點卡顯示名稱、地址與座標，Figma 動作列使用 Primary Active「Start／開始」（77 × 40 pt，play icon）置左；右側 Star 使用 B `Standard / Enabled / Large`、Copy 使用 B `Copy / Enabled / Large`（各 44 × 44 pt，純 icon）；查看與複製不送點；點「收藏」（星號）彈出編輯最愛 sheet（C2）編輯標籤，點「儲存」才真正新增；本次新增的刪除入口僅適用瞬移面板目前位置與下方最愛列的星號，不改變地點詳情卡的編輯行為 |
| 最愛地點 | C1–C4 頁面底為 `canvas`，清單置於左右 16 pt、NavBar 下方 16 pt、圓角 16 pt 的單一卡片；Figma 目前渲染為 NavBar y=54–98、清單 y=108（10 pt gap），App 依 2026-10-30 使用者指定使用 16 pt，差 6 pt。每列 64 pt，星號／勾選命中框與 ⋯ 命中框 44 pt，文字由 x=76 pt 起，分隔線縮排 60 pt 並於右側留 12 pt，末列不畫分隔線。C1、C4 顯示可復原 snackbar，成功圖示為 Figma `icon/okfill` 雙色圓形 check；C3 依 Figma 顯示「已選取 2 項」，選取第 2、4 列並以底部紅色「刪除（2）」批次刪除。C2 為 367 pt 編輯 sheet：輸入卡為 `surface/input`，空白提示文字是「標籤」且清除叉號常駐；地點資訊卡用 `canvas`，下方主按鈕「儲存」使用 primary。按鈕上方與資訊卡保留 40 pt；依 2026-10-30 使用者追加要求，按鈕下方至 Home indicator 的內容留白改為 40 pt（此值高於目前 Figma 渲染的 20 pt 間距，App 按使用者要求）。點星號或清單 ⋯ 開啟編輯；已收藏項目可在 sheet 內刪除；刪除後約 5 秒可復原。瞬移面板「目前位置」與下方最愛列的星號開啟 sheet 時，收藏項目在右上顯示紅色「刪除」；其他入口維持既有刪除規則。底部搜尋只查最愛。以上視覺以 Figma 04 C1–C4 Light／Dark 渲染為準，App 三語文案與 `Font.system` Theme style 同步。 |
| 路線編輯與面板收合 | 路線規劃支援單一節點清單與「高度最窄 panel UI」（D17，高 76 pt）：收合時僅呈現「規劃路線」標題與右上最愛星號、GPX 資料夾按鈕，完全隱藏起訖點清單、時速、來回開關與開始按鈕，最大化路徑視野；向上滑動或點擊標題還原展開為 D1 完整面板。自動收合只由地圖候選 Pin 觸發（放置／點選 Pin，D1b／D4），單純拖曳、縮放地圖不收合；確認 Pin 後返回 D1 完整面板（2026-10-24 使用者確認）。D1 與 D6 全面移除 Km / 速度摘要列（Summary row），面板高度緊湊縮減（D1 高 369 pt（2026-10-24 Figma）、D6 高 467 pt），大幅增加底層地圖路徑視野。進入路線 tab 時 D1 以完整面板呈現，不自動開啟 D5 或鍵盤；起點預設為目前位置（有最後模擬位置或真實 GPS 時），兩者皆無時起點留空。預設選中「起點」；路線選中列使用 primary 邊線與中性底（Light＝card、Dark＝active），不使用 primary 底。起點與終點 input 右側常駐清除按鈕（✕，44 pt 命中；空值時停用），清除後欄位保留為空值；中途停靠點以紅色 ✕ 刪除整列；兩者皆不顯示任何 toast／snackbar（2026-10-26 使用者指示，取代 D9 可復原 snackbar；Figma D9 未同步）。畫面始終保持「單一選中的路線地點」（起點、途經點或終點）；第一次點擊欄位選取，第二次點擊同一欄位才開啟 D5 搜尋；改點其他欄位時先選取新欄位，再次點擊才開啟 D5。D4 Pin 的「確認」回填目前選中欄位；Figma LocationCard CTA 為 Go（App 尚未同步）；頂部搜尋列仍可直接開啟 D5。起訖點具備時自動預算路徑；無法規劃路線時以頂部獨立 Toast warning 警示。GPX 載入後唯讀 |
| 點選地圖選點（D4／E4） | D4（原 D1.a）點選地圖候選 Pin 時，下方彈出浮動 `Light · LocationCard / Layout=Route`（361 × 180 pt、圓角 16 pt、無邊框、95% Light overlay surface、陰影），直接覆蓋在高度最窄 panel 上方（y = 573，TabBar 上方 16 pt）；Pin 上方維持「確認」，卡片 CTA 依 2026-10-28 Figma 更新為 Go。E4 漫步 Pin 也使用共用 `Layout=Route` 地點卡（361 × 180 pt、圓角 16 pt）；PinConfirm 保留「確認」，卡片 CTA 使用 Go；卡片出現時搖桿 panel 自動收至最小高度並保持，拖動 grabber 拉高或點搖桿 tab 展開，關閉卡片不恢復舊高度。淺深色結構與行為一致，細節依 Figma 對應畫面為準 |
| 路線細節／執行 | 執行模式（D6，原 D3）與中斷恢復模式（D10 系統中斷、D10.a 使用者暫停）隱藏搜尋與 tabs，頂部執行指示卡（Light 使用 95% overlay surface 及 Light 文字色；Dark 維持 Dark theme）。底部控制面板之中間功能列全面改為純 icon 線框按鈕（Light 白底、Dark `#2C2C2E` 控制表面，0.5 pt 細邊界、微陰影，無文字標籤），左側配置「來回」（開啟為 `repeat`，關閉為 `repeat.slash`）與「順向／逆向」（垂直上下箭頭：順向為左箭頭朝下較淺、右箭頭朝上深黑；逆向為右箭頭朝上較淺、左箭頭朝下深黑；且只有來回開啟時才顯示此按鈕，來回關閉時整顆隱藏，固定順向；2026-10-26 使用者指示，App 已依 Figma `icon / repeat`、`icon/repeat-off`、`icon/direction-forward`／`icon/direction-reverse` 重繪，未裝置驗證；來回開啟時進度條下方不再顯示「0% 起點／100% 終點」小字，避免面板高度跳動），右側配置時速設定線框按鈕（Speed chip，統一改為無單位文字，僅呈現圖示與純數字，如「9」）；最下方為結束與暫停／繼續按鈕；點擊「結束」直接結束路線並保留目前位置（2026-10-26 使用者指示：取消 D6.a 確認結束浮窗，Figma D6.a 已廢棄，待同步移除，未裝置驗證）；D10 與 D10.a 主按鈕均為「繼續」（play 圖示），D10 為系統異常暫停帶 Warning Toast，D10.a 為使用者主動暫停無 Toast |
| 中斷狀態提示與各模式面板（B8/B9、D10、E5） | 瞬移 B8/B9 共用頂部獨立 Warning Toast（80 pt；Light 暖琥珀底 `#FFF6E6`，Dark 使用 Warning surface token；1 pt 警示橙邊 `#E39A18`（2026-10-31 由 #FF9500 更新）、說明、Light 白色／Dark 深色表面「重試」膠囊與 ✕）；底部維持 B1 標準瞬移收合面板，顯示位置標籤、名稱、座標、收藏與複製，不顯示 Resume 按鈕。B8 有新鮮真實 GPS 時標「目前位置」並用實心藍 RealArrow；B9 無新鮮真實 GPS 時標「最後模擬位置」並用灰色箭頭。路線 D10 與漫步 E5 才使用各自的窄版 Resume 面板與恢復 CTA。B8/B9 顯示以 2026-10-26 Figma 04 實際渲染讀回為準。 |
| GPX／已匯入路線 | **2026-10-30 D11–D18 更新**：D1 資料夾入口推入全螢幕已匯入路線清單（D11）；點列顯示 D12 底部 action card，使用黑色 40% Dim、四個 56 pt 動作列與獨立取消列，隱藏且停用後方匯入 CTA。D13 是全螢幕唯讀點位頁，頂列共用「返回／置中標題」導覽列；檔名／點數資訊列下方右側顯示小字「唯讀」，不放在導覽列。D15 在路線面板以起點／第 2 點／中間 N 點／終點及查看全部入口摘要長路線，≤10 點則完整列出。D14 保留原生系統分享 sheet，D16 保留原生檔案選擇器；D17 成功 Snackbar 懸浮在匯入 CTA 上方，D18 失敗 StatusBanner 懸浮在 header 下方並保留重試與關閉，不推動清單。全頁 canvas、清單與點位列表 card、分隔線用 separator token；D6 路線面板仍保留對稱收藏星號與 GPX 資料夾入口。現有 `ImportedRouteRecord` 只存檔名、起訖座標與點數，無法呈現 Figma 樣例的具名端點與距離；原生分享／檔案選擇器的系統外觀會隨 iOS 版本與模擬器資料改變。App 實作與系統畫面差異分開記錄於票 13，Figma 未修改。|
| 最愛路線與檢視路線 | D19 使用 canvas 背景、左右 16 pt 單一 card，六列各 64 pt，星號／名稱／⋯ 對齊 Figma；末列不畫 divider。底部搜尋欄包含系統 UIPasteControl，Figma placeholder 渲染為「搜尋最愛地點」但仍只篩選最愛路線。D20 為 D19 上的編輯 sheet，取消／刪除列、路線標籤欄、路線資訊卡與主按鈕；不自動叫出鍵盤，儲存按鈕下方依 2026-10-30 使用者要求留 40 pt。距離欄位尚未存在於 `FavoriteRouteRecord`，不可用直線距離假造。D21 多選依 D22 結果選第 2、4 列；Figma D21 第 5 列另有一個勾選圖形與數量文字衝突。D22 顯示可復原 snackbar，使用 success check 圖示。D23 為全螢幕「全部地點」清單頁（由 D1「檢視路線」推入），返回鍵＋置中「全部地點」標題，左右 16 pt 單一卡片列出序號、地點名稱與角色（起點／停靠點 N／終點），末列不加分隔線；卡片下方為「＋ 新增停靠點」與「⇅ 反轉順序」（垂直反轉 icon，使用 `GoFlyIconAsset.swapVertical`）。最大 Dynamic Type 時列高增長、footer 垂直重排，均在 ScrollView 內可捲動不裁切。 |
| 搖桿／漫步 | 刻度使用次要圖示灰並以 50% opacity 呈現（Light `#8A8A8E`、Dark `#98989D`）；N/E/S/W 方位字使用次要文字灰。陰影、拖曳高亮、觸覺與回彈維持既有設計；一般與漫步共用 150 pt 搖桿。E1、E2、E3 的 Speed chip 緊湊貼合純數字（寬度收整為 68 pt）。隨機目的地為帶 ⟳ 的次要按鈕。漫步結束需確認，呼叫既有取消入口並保留最後模擬位置；E1 與 E5 左上方狀態標籤使用 Light 共用元件或 Dark `Dark · 0 · 共用元件` 中的 `StatusPill / neutral`（Light 白底、Dark `#2C2C2E` 表面、0.5 pt 邊框、雙層陰影、灰色圓點；文案改依 2026-10-24 五態規則動態顯示，取代舊版黑色實心底與英文字） |
| 準備／修復／背景通知 | 錯誤統一為 StatusBanner，修復指引在說明內，保留 loading 與既有重試／取消／設定／返回可用性；一次性結果以 2 秒 snackbar 呈現，不把畫面更新視為命令成功 |
| 設定首頁 | 錯誤與警告 toast（StatusBanner，含 Wi-Fi 未連線錯誤）置於最上方（服務卡與分組設定之上），確保錯誤即時可見；分組設定之連線項目新增「Wi-Fi」（右側顯示已連線／未連線，點擊跳轉至 iPhone Wi-Fi 設定）；分組底面、32 pt 單色圖示區、64 pt 最低行高、內縮分隔線；長狀態值可上下重排；服務卡與 GPS 狀態分層 |
| 設定子頁／說明 | 定位、背景、VPN、語言、外觀、裝置與簽名、說明使用原生導航；偏好設定的語言與外觀各自使用獨立原生子頁（點語言僅顯示語言 options，外觀分開獨立顯示，不合併在同一分頁）。拒絕定位標 warning，使用期間屬正常；裝置頁保留診斷匯出 |
| 首次交接／資料鎖定／還原 | 沿用共用按鈕、字體及卡片 token；不更動資料交接、准入及修復邏輯，不以裝飾掩蓋失敗提示 |

## 自適應與無障礙驗收

- 中文：繁中／簡中都由系統字體呈現；不得新增 `UIAppFonts`、`.custom` 字型或網路字型；數值使用等寬數字不影響中文。
- 字級：標準字級與 Accessibility XXXL；文字不縮小來塞進固定框，長標籤／狀態可重排或捲動；搜尋、確認、取消與星號須可觸及。
- 深淺色：文字、卡片與主次 CTA 依語意色切換；選取、失敗、停用不能只靠顏色判別。
- 操作：最少 44 × 44 pt；選點、最愛、詳情、排序、刪除與開始各維持獨立目標；地圖露出區依實測面板高度計算。
- 固定高度的 chrome（bottom bar、浮動搜尋列、狀態 pill）在 Accessibility 字級上限為 `accessibility1`（與 UIKit tab bar 相同），避免三個等寬 tab 互相擠壓；sheet 與面板內文不設上限。
- 原生能力：保留系統鍵盤、手勢與 VoiceOver 標籤；裝飾圖示不加入朗讀；沒有新增持續動畫，支援減少動態效果。
- 圖示：`GoFlySymbols` 是 Figma 04 共用向量 icon catalog 的語意別名，實際繪製統一經 `GoFlyIcon` 與 `Assets.xcassets`；一般單色功能圖示使用空心描邊，不以 SF Symbols 代替。播放／暫停／停止、選中星號、地圖位置箭頭、速度插圖與狀態圖示依 Figma 保留實心或語意色。齒輪、重定位、關閉、重試、排序、匯入／匯出、外部連結同一用途使用同一 catalog asset；目前／模擬位置、候選 Pin 與目的地各可辨識。
- 驗證順序：專案 `check.sh`、既有對應 UI 測試、模擬器截圖檢視；手機 VoiceOver、觸感與定位／背景效果集中於裝置驗收。

## 完成度與證據

以上為本次 App 精修範圍，並非 Figma 視覺稿更新。驗證結果與截圖索引記錄在 `work/gofly-ios/design-polish/RESULT.md`。模擬器／建置通過不代表真機定位、GPS、VPN 或接收 App 行為已通過。

設計依據：`ios-hig-design` 與 `mobile-ios-design` skills，以及 Apple [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)／[Typography](https://developer.apple.com/design/human-interface-guidelines/typography) 的原生版面與語意字級方向。

## 地圖語言的可實作範圍

App 偏好語言優先用於介面、marker 輔助標籤，以及點選地點的反向地理編碼地址。`MapKitPlaceResolver` 在每次建立 request 時讀取最新偏好，設定 `MKReverseGeocodingRequest.preferredLocale`；系統選項使用 nil 以沿用 MapKit 預設，不需要替換地圖、移動鏡頭或重建任務。

查核已安裝 iOS 27.1 SDK：`MKMapView`、`MKMapConfiguration`、`MKLocalSearch.Request` 未提供每張底圖／搜尋結果的 locale 設定。底圖地名與 POI 標籤仍由 iOS／Apple 地圖及可用資料決定，不宣告已隨 App 偏好翻譯；名稱搜尋原樣送出使用者輸入，並以目前地圖可視區域作為 MapKit 搜尋提示，不維護程式內的中文別名表。MapKit 的搜尋區域僅提供相關性提示，不保證結果限於該區域或 Apple 地圖資料中一定存在該地點。既有最愛、歷史搜尋與使用者標籤也不改寫。可用公開 API 見 Apple [MKLocalSearch.Request](https://developer.apple.com/documentation/mapkit/mklocalsearch/request)。

本輪圖示、Pin、輸入對比與地址語言的驗證位於 `work/gofly-ios/icon-refinement/RESULT.md`；Debug Simulator 元件預覽只驗證繪圖，不提供 GPS、服務或 ACK 證據，也不編入 iPhone target。

## Google Maps 參考改版（2026-10-20）

**視覺主來源（2026-10-23 使用者再次確認，並要求未來 UI 開發持續參考）：Figma 檔案 `RtPV8PXCQJ2WXK3jk3kPrq`（「GoFly · UI 線框討論」）→ 頁面「`04 · iOS Redesign（Google Maps 參考）`」（`node-id=121-50359`，含同頁「`Dark · `」前綴深色版）是 GoFly iOS UI 開發的主要視覺基準（[開啟 Figma 頁面](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359&t=PbhqDtFqyHZubseg-1)）。每次 iOS UI 實作或線框工作前都要查閱當前頁面；本文件補充行為與無障礙規則。若畫面規格和 Figma 不一致，依 Figma 視覺稿並在同一工作更新本文件及驗收條件。地圖底圖仍為 Apple Maps，Figma 地圖只作線框示意，不視為不一致。**

**狀態（2026-10-30）：Figma「04 · iOS Redesign（Google Maps 參考）」為目前 iOS 唯一視覺基準，靜態、不含 prototype。只讀 frame catalog 目前列出 64 個可渲染 frame ID；Light、Dark 各有 64 張對應畫面，包含 B11 Dark（node `322:40470`），不再把 B11 列為設計缺口。R06 仍沒有 frame。共用色彩／元件參考區包含 Common Color、Light／Dark Color Scheme、Light／Dark UI 與按鈕、Icon、Typography；舊 `0 · 共用元件（正式版 token）` 已刪除。畫面與本文衝突時以渲染出的 Figma 畫面為視覺依據；App 實作、程式驗證與真機驗收分別記錄，不由線框推定已完成。** 頁面與規格差異見 [`FIGMA-UI-RECONCILIATION.md`](FIGMA-UI-RECONCILIATION.md)。

### 取代的規則

| 原規則 | 改版後 |
| --- | --- |
| 地圖頂部：位置來源／服務狀態卡＋啟停＋設定 | 浮動搜尋列（右側齒輪＝設定）＋狀態 pill；頂部不放啟停／暫停 |
| 面板內的瞬移／路線／搖桿膠囊模式列 | 底部 bottom bar 三個等寬 tab；最愛不設 tab |
| 搜尋在面板內輸入 | 全螢幕搜尋頁；鍵盤出現時隱藏地圖、pill、tabs |
| Go 位於候選 Pin 上方；點選置中候選 Pin | Go 兩處、同一動作：候選 Pin 上方小型 Go（約 28 pt 高，維持 44 pt 點擊範圍）＋地點 sheet 動作列第一個黑色按鈕；sheet 不放自明說明（如「Go 會把模擬位置移到此地點」）；點地圖不自動置中，Pin 被 sheet 遮住才最小平移 |
| 路線欄位選定後須確認才提交 | 點選結果即回填並返回；返回鍵取消 |
| 最愛：點星號即刪除；長按編輯標籤 | 點星號新增或 ⋯ 編輯：彈出「編輯最愛」sheet（C2，右上「刪除」文字按鈕、下方「儲存」主要按鈕，點儲存才保存）；清單列左側星號等同右側 ⋯，點擊開啟編輯 sheet（不作為刪除開關，刪除由編輯 sheet 內之刪除按鈕或多選刪除負責；2026-10-26 使用者指示）。「選取」多選批次刪除；底部固定「搜尋最愛地點」欄位（只搜尋已收藏地點） |
| 路線收藏與管理：缺少最愛路線 UI/UX | D1 右上星號改為開啟最愛路線清單（D14）；D1 下方開始按鈕左側新增星號按鈕（按一下開新增最愛路線 sheet D15 編輯標籤，儲存後轉實心星號，再按一下刪除轉為空心）；最愛路線清單支援自訂標籤、路線起訖/距離摘要、清單 ⋯ 編輯與多選批次刪除（D16，沿用規則 #10 批次刪除與可復原 snackbar 機制） |
| 路線／漫步執行時沿用一般面板 | 執行模式：隱藏 tabs 與搜尋列，頂部執行指示卡（Light 使用 95% overlay surface 及 Light 文字色；Dark 維持 Dark theme），底部固定控制面板 |
| 右側地圖控制含圖層與指北 | 全模式固定單一「回到定位」圓鈕（44 pt），固定在 panel 上緣上方 16 pt、距右緣 16 pt；不提供圖層鈕、指北針鈕或跟隨方向鈕 |
| 定位權限要求升級「永遠」 | 只請求「使用 App 期間」，顯示目前權限狀態，不提示升級 |
| 錯誤只用黑白高對比文字／面板內橫幅 | 系統訊息統一採用獨立 Toast UI（danger／warning／success），浮動於頂部搜尋列／top bar 下方，不加在 panel 上面或裡面；一律具備 ✕ 關閉圖示，可手動關閉或定時收合；一次性結果用 snackbar（2026-10-22 使用者確認取代原面板頂端 StatusBanner 規則） |
| 漫步地點卡堆疊在 panel 內 | 漫步 Pin 的地點卡為獨立浮層，覆蓋於底層操作 panel 上面（不內嵌或堆疊於 panel 內）；右上角使用共用 B Clear icon button；候選 Pin 的 PinConfirm 保持「確認」，LocationCard CTA 使用 Primary Active「Start／開始」。卡片出現時底層搖桿 panel 收至最小高度並保持；拖動 grabber 拉高或點搖桿 tab 展開，關閉卡片不會自動恢復較高 detent（2026-10-24 使用者確認） |
| 設定首頁錯誤 banner 置於底部／偏好設定合併於單一頁面 | 設定首頁錯誤 toast（StatusBanner）置於頁面最上方；偏好設定的語言與外觀各自獨立分頁顯示，不合併在同一分頁（2026-10-22 使用者確認） |
| 錯誤與警告 UI 放置於 panel 內或頁面下方／缺乏 Wi-Fi 連線監控 | 所有 warning、error UI 統一改為獨立 Toast UI（isFloating），不放在 panel 中，也不放在頁面下方；新增 Wi-Fi 連線監控（由 GoFlyNetworkMonitor 同步管理），若非 Wi-Fi 連線，在 App 首頁與設定頁同步跳出「需要連接 Wi-Fi」error toast（B10，原 B7.a / R01.a 移動至地圖首頁 B 區第 2 行，底層為 B1 sheet 收合，水平置中 x: 16, w: 361，樣式與顏色完全對齊 B7，純提示無按鈕，帶 ✕ 關閉）；設定首頁新增 Wi-Fi 連線項目，顯示已連線／未連線並可點擊開啟系統 Wi-Fi 設定；R06（原 R04.a）VPN 失敗 Toast 樣式與顏色亦同步對齊 B7（水平置中，帶白色膠囊重試按鈕）（2026-10-22 / 2026-10-24 使用者確認） |
| 首次安裝後缺少 Mac 配對簽名引導 | 正式裝置首次啟動且尚無 setup handoff 時顯示 R07；依 Figma 04 的實際渲染，只呈現 120 pt Mac 圖示、標題、USB 配對／簽名說明及中性「尚未配對」pill，置中排版，沒有步驟列或底部按鈕。Mac 完成配對後，iPhone 回到前景時重新檢查 handoff 並進入正式 setup；模擬器維持一般啟動。Figma R07 節點說明另提及「檢查連線狀態」及「連線說明」，但渲染畫面沒有這些控制，實作以渲染為準，狀態檢查由回到前景觸發（2026-10-26） |
| 路線選點僅限文字搜尋與點選回填 | 支援由 D1 路線規劃模式直接在地圖上移動放置大頭針或點選任意地點設定選中地點（D4，原 D1.a，Pin 上方浮動純文字「確認」黑底膠囊，無圖示，取代原 D2a「從地圖上選擇」）；同時支援直接點擊地圖大頭針浮動「新增」按鈕直接設為目的地（D1b，純文字「新增」，無圖示；2026-10-24 已廢止，改由 D4 回填選中欄位）；D1 面板預設選中起點 input 且外框滿框（w: 353, cornerRadius 14 pt），起訖均具備清除按鈕（✕）；新增 D2（原 D1.2）多停靠點滑動容器（5 個路線地點，最多顯示 4 個點位，支援垂直捲動並具備滾動指示器；面板標題、＋ 新增停靠點、反轉順序與底部開始按鈕均固定於容器外）；Figma D9（原 D1.b）曾畫刪除／清空路線地點 success toast 與「還原」按鈕（2026-10-26 使用者已確認不顯示，見下方 D9 補充）；D22（原 D16.a）最愛路線清單刪除路線 success toast 浮動於底部紅色「刪除 (2)」按鈕上方（y: 618 pt，帶「還原」按鈕）；底層 panel 均自動縮為高度最窄 UI（D3，原 D17），上方浮動地點卡（LocationCard，高 180 pt，圓角 16 pt，浮於 TabBar 上方 16 pt 覆蓋 panel），PinConfirm 保持「確認」；D4 LocationCard 使用 Go（Figma 視覺已更新，App 尚未同步）；D5（原 D2）搜尋選單移除「從地圖上選擇」（2026-10-23 / 2026-10-24 使用者確認） |
| 地點卡排版跑版、關閉鈕跑版與複製缺乏反饋 | Light LocationCard 操作列由共用 Primary Active「Start／開始」（77 × 40 pt）置左；Standard Star 與 Copy Enabled Large（各 44 × 44 pt）置右；右上 Clear Enabled Large（44 × 44 pt）；卡片無描邊並使用 95% `color/surface/overlay/location-card` 與 12 pt 背景模糊，選點彈出卡片時底層 bottom panel 自動收合至 `.collapsed` 最小高度；點擊 Copy 複製座標觸發黑底成功 Toast（Snackbar「已複製座標」）（2026-10-23 使用者確認） |
| 首頁半開清單與全螢幕搜尋混合最愛與歷史 | 地圖首頁 B2 sheet 半開移除歷史清單（僅保留目前模擬位置與最愛地點前 2 筆＋查看全部）；全螢幕搜尋 B3 空輸入頁面移除最愛地點（僅保留座標提示與最近搜尋，右側置右新增「清空記錄」純文字按鈕，圖標使用 `clock.arrow.circlepath` 歷史時鐘）；B4 搜尋結果地點圖標使用 `mappin`（2026-10-23 使用者確認） |
| 無真實 GPS 觸發警告並阻擋操作／Go 按鈕禁用條件過寬 | 室內無 GPS 訊號屬於模擬常態，全面移除無真實 GPS 時的 warning/error toast 橫幅，且不得阻擋 Go 按鈕；Go 與 Pin Go 共用核心操作允許條件：忙碌中、未確認操作或 VPN 通道斷線時 disabled；沒有真實 GPS 不阻擋 Go（2026-10-23 使用者確認） |
| 啟動連線會話未建立與錯誤狀態不一致 | App 開啟自動背景建立 connection session，啟動瞬間不顯示錯誤；地圖 status pill 與設定頁連動，斷線時文案統一為「連線中斷」（取代 Needs attention / 需要注意）；冷啟動 LaunchScreen 預設隱藏進度條，僅在啟動超過 0.5s 時由 StartupView 顯現，對齊 R01（2026-10-23 使用者確認） |
| 路線規劃面板僅有全開狀態且高度過高 | 路線規劃 panel 大幅精簡高度：全面移除 Km / 速度摘要列；D1 高度縮至 429 pt（省下 70 pt 視野），D15（原 D6）高度縮至 467 pt（省下 42 pt 視野）；D15 移除「匯入路線・不可編輯」副標題，點位清單卡上移至 y = 68（對齊 D1），右上補齊星號與 GPX 資料夾雙圖示，清單卡下方新增 `🗑 清空路線` 文字按鈕（採標準中性黑圖示與文字，非錯誤紅）；同時支援高度最窄 panel UI（D3，原 D17，76 pt 可視），完全隱藏起訖清單與開始按鈕，讓出最大地圖視野（2026-10-23 使用者確認） |
| 瞬移中斷時錯誤地將 panel 換成 Resume 面板 | 瞬移（B8/B9，原 B8/B8.a）、路線（D10 系統暫停、D10.a 使用者暫停）、搖桿漫步（E5，原 E3）皆在頂部獨立顯示 Warning Toast；採 100% 實心暖琥珀底 #FFF6E6、1 pt 警示橙邊 #E39A18（2026-10-31 更新）、高 80 pt，右側提供白色膠囊「重試」與 ✕ 關閉。B8/B9 底層維持標準瞬移收合面板（120 pt）：保留位置標籤、名稱、座標、收藏與複製，不放 Resume 按鈕；新鮮真實 GPS 顯示「目前位置」（B8）及藍色 RealArrow，無新鮮 GPS 顯示「最後模擬位置」（B9）及灰色箭頭。路線 D10 與漫步 E5 才顯示窄版 Resume 面板，分別提供「繼續路線」與「恢復漫步」。 |
| 全域狀態標籤 Token 不一致 | B8、E1、E4 的左上狀態標籤全面對齊 Light 共用元件（白底 `#FFFFFF`）；Dark `Dark · 0 · 共用元件`（`#2C2C2E` 表面；0.5 pt 細邊框 `#C6C6C8` 45% 透明度、雙層柔和陰影、圓角 15 pt）：B8（瞬移中斷）為黃色語意圓點 +「暫停」（2026-10-24 更新，實際色彩 token 與 Figma 待同步核對）；E1（搖桿待命）與 E4（漫步選點，原 E5）為中性灰圓點 `#8E8E93`；文字依 session 任務階段使用「啟動」或「停止」（2026-10-24 更新）（取代舊版黑底與英文 "Running"）（2026-10-23 使用者確認） |
| 路線執行模式控制列帶文字標籤且缺乏時速調整 | D6/D10（原 D3/D4）控制面板之中間功能列全面改為純圖示線框按鈕（白底、0.5 pt 細邊框、微陰影，無文字標籤）：左側配置「來回」（開啟為 `repeat`，關閉為 `repeat.slash`）與「順向／逆向」（垂直上下雙箭頭：順向左下淺右上深、逆向右上淺左下深；且只有 REPEAT 啟用時才可切換逆向，關閉時鎖定置灰），右側配置時速設定按鈕（Speed chip，統一取消單位文字 `km/h`，僅呈現圖示與純數字，如「9」）；E1、E2、E3 的 Speed chip 緊湊收整為 68 pt（2026-10-23 使用者確認） |

### 新增 token（淺色值；深色依 iOS 系統色自動對應）

| Token | 值 | 用途 |
| --- | --- | --- |
| danger | `systemRed` #FF3B30；文字 #D70015 | 錯誤圖示、banner 邊與底（12%） |
| warning | `systemOrange` #FF9500；文字 #C93400 | 受限、權限不足 |
| success | `systemGreen` #34C759；文字 #248A3D | 需確認的成功、pill 色點 |
| snackbar | #1C1C1E 底、Dark `#E5E5EA` 前景 | 不需處理的結果 |

深色值（Figma Dark 版）：畫布 `#1E1E1E`、卡片／導覽表面 `#2C2C2E`、控制表面 `#3A3A3C`、輸入底 `#1C1C1E`、分隔線 `#38383A`、邊框 `#48484A`；主／次／停用文字 `#E5E5EA`／`#98989D`／`#636366`；Primary action 為 `#0066CC` 表面＋`#E5E5EA` 前景；danger／warning／success 為 `#FF453A`／`#FF9F0A`／`#30D158`。使用語意色 token，不在畫面寫死色碼。

其餘沿用本文件既有 token：`label`、`secondaryLabel`、`systemBackground`、`secondarySystemBackground`、`systemGray5` 輸入底、`separator`；主面板 20 pt、搜尋／地點 14 pt 連續圓角；浮層陰影 9%／y 5。

### 改版驗收條件（逐項結果見交付記錄）

- Bottom bar 三個 tab 等寬，標準與 Accessibility 字級都不截斷；執行模式與全螢幕頁面隱藏。各模式 TabBar 完全對齊 `B1 · 地圖首頁 / sheet 收合`，無 filled color，選中模式僅純線框 line 變深（stroke 2.29 pt、#000000 / #E5E5EA），未選中為細線次要灰（stroke 1.88 pt、#999999 / #8E8E93）。Section B 為瞬移高亮、Section D 為路線高亮、Section E 為搖桿高亮。
- 鍵盤出現時沒有任何面板被擠壓或遮住輸入框；搜尋框與結果列在外觀上可區分。
- 點地圖放 Pin 時鏡頭不動；Pin 被 sheet 遮住時才平移且平移量最小。
- 地圖鏡頭（2026-10-25 使用者確認）：只有三種時機會自動移動或縮放鏡頭——App 初始（第一個鏡頭）、使用者確認設定地點（選取搜尋／最愛地點、瞬移 Go 收到 ACK、確認路線地點或載入最愛／匯入路線後框住路線、確認漫步目的地），以及點「回到定位」。之後的 GPS 定位更新、切換 tab、自動設定的搖桿／漫步起點、漫步自動續段或隨機目的地、刪除／清空路線地點都不改變鏡頭。只平移的鏡頭意圖保留使用者目前縮放；「回到定位」一律回到預設距離（可見地圖寬約 500 m（2026-10-31 由 1 km 拉近，25 km/h 才有明顯移動）），連點不會越拉越遠。
- 路線欄位點選結果一次即回填並返回；返回鍵保留原值。
- 最愛地點與最愛路線清單列左側星號等同右側 ⋯：點擊開啟編輯 sheet 改標籤（不具點擊取消功能；刪除由編輯 sheet 內之刪除按鈕或多選刪除負責；2026-10-26 使用者指示，未裝置驗證）。多選刪除後同樣可復原。
- 地圖首頁未開始模擬時，收合面板顯示「目前位置」（模擬中則顯示「目前模擬位置」）；進入地圖時即時取得並顯示 GPS 位置。
- 位置箭頭 UI 依 Figma 規格：模擬位置（SimArrow）採 22×22 frame，向量尺寸 12.83×17.42 pt，與 24 pt `icon/nav` 縮放至 22 pt 後一致，Light 黑色填色＋白色描邊，Dark `#E5E5EA` 填色＋黑色描邊，不使用綠色或紅色；等待態沿用相同黑白配色並以 50% opacity 呈現。真實位置（RealArrow）與 SimArrow 共用 22×22 frame 及相同箭頭向量輪廓／尺寸，保留實心藍色（`#007AFF`）、`#E5E5EA` 外框與微陰影，不使用空心；中斷後具真實 GPS 之畫面（B8/Dark B8）地圖位置箭頭使用實心藍色 RealArrow。漫步與路線執行時，連續新鮮的模擬位置小幅變化須平滑補間，箭頭方位須沿最短角度平滑轉動；首次定位、位置狀態切換與大幅跳點直接更新。這是程式行為要求，尚待實機畫面驗證。
- 2026-10-23 模擬定位未確認 UX：連線失敗、失去背景執行權或未取得持續執行權就離開前景時，保留最後 ACK 座標並將箭頭轉為灰色等待狀態；回前景、VPN 通道探測成功或 session warmup 均不能單獨恢復正常箭頭，需新的定位 ACK。有效背景 grant 且持續 ACK 的路線／漫步維持正常箭頭。未確認模擬位置不單憑殘留座標顯示綠色「模擬中」；pill 依下方 2026-10-24 五態規則與實際任務／連線階段判定，不再使用「受限」，原因另由提示說明。這是保守的未確認呈現，不表示能偵測原生 session 的確切斷線時刻。新的固定位置維持與授權內 session 修復規則見背景章節；已轉灰的箭頭需恢復 ACK 才能還原，若系統已收回執行權，回前景後仍需明確重試；背景路線有 grant 時仍正常、到期後轉灰。程式與真機畫面驗證分開記錄。
- 手機可獨立瀏覽、選點及編輯候選；實際 Go／移動仍須有效配對及定位服務。2026-10-22 除錯更正：配對缺少、準備失敗或未實際送點時，不得宣告成功、更新模擬位置箭頭或清除候選；清除定位／重置通道失敗亦須如實呈現。這取代先前無配對也視為送點成功的規則。協定 ACK 與 Apple 地圖／Google Maps 接收位置分開驗收；程式修正不代表真機定位已通過。
- 首次引導 VPN 通道失敗頁面的檢查連線按鈕文字不再定時閃爍，且下一步按鈕固定不跳動。
- 點選星號只開啟「編輯最愛」sheet（C2），不直接刪除。地圖首頁 B1「目前位置」與瞬移面板下方最愛列的星號，在地點已收藏時於 sheet 右上顯示紅字「刪除」；地點尚未收藏時不顯示。地點詳情 sheet B5 與其他入口維持原有刪除規則。Sheet 下方為「儲存」主要按鈕（Light `#007AFF` 底、白字；Dark `#0066CC` 底、`#E5E5EA` 前景），左上「取消」；點儲存才保存標籤／新增，點取消不寫入。此互動於 2026-10-26 由使用者確認；Figma 04 現已使用共用 Primary Active variant。
- 瞬移／手動搖桿候選 Pin 上方與地點 sheet 都有 Go，兩者觸發同一瞬移；「位置待確認」時兩者都停用。
- 全螢幕搜尋（2026-10-30 依當前 Figma 04 B3／B4 渲染更新）：B3 空 query 欄位不顯示 placeholder 或清除 ✕，右側保留貼上 icon；「最近搜尋」標題下方使用單一卡片列出最近兩筆，鍵盤可見。B4 query 顯示「台北」，先呈現「前往座標 25.04780, 121.51700」列，再以單一卡片呈現四筆附近地點與距離；系統鍵盤為原生控制，Figma 鍵盤僅示意。Light／Dark 結構相同，卡片使用 card、頁面使用 canvas，貼上仍使用安全的系統 `UIPasteControl`。最近搜尋列右側配置「清空記錄」純文字按鈕（次要文字顏色 secondaryLabel，PingFang TC 15 pt Medium，右緣對齊 373 pt／距邊 20 pt，對齊清單列右緣）；點擊觸發清空記憶體搜尋歷史（2026-10-23 Figma UI 規格更新，程式行為與實機待接續更新驗收）。Figma 設計已同步；App 實作及裝置驗證狀態另行追蹤。
- 冷啟動狀態 pill（2026-10-24 使用者更新，取代 2026-10-23「服務待命 / Standby」）：本次 session 建立且尚未開始模擬時顯示灰色「啟動」。上次模擬座標只是歷史資料，不提升為已確認，也不恢復任務。尚未建立 session 的初始化進度另行表達，不偽稱已連線。此為待實作的新規格；Figma 冷啟動五態變體尚待核對，不宣稱已同步。
- 連接中 pill（2026-10-26 使用者確認，補充上述五態為六態）：App 啟動或重連時，建立 VPN tunnel／移動許可的過程中，status pill 顯示黃色（warning）「連接中」（en `Connecting`、zh-Hans `连接中`），此階段不跳 error toast（App 自行中止的 cancelled 不視為錯誤）；建立成功後依狀態轉「模擬中」或「啟動」，建立失敗才轉紅色「錯誤」並顯示 toast。搖桿模式有目前位置或最後模擬位置時，建立完成自動進入「模擬中」。Figma 04 頁有 Light／Dark 共用 `StatusPill / 連接中` 與 B11 成對畫面（Dark node `322:40470`）；程式已改（`SessionDisplayStatus.connecting`），實機待驗。
- 三模式模擬狀態 pill（2026-10-24 使用者更新，取代瞬移「執行中 / Running」）：瞬移／固定定位、路線、搖桿（含漫步）執行中的 session pill 統一為綠色「模擬中」。正常探測或補送等待 ACK 不切換 pill；暫停為黃色「暫停」，停止為灰色「停止」，兩者均保有連線 session。任何共用狀態錯誤均顯示紅色「錯誤」，並保留具體原因。此為待實作規格，未修改 Figma，實機待驗。
- 錯誤 banner 的說明內含修復指引（例如持續失敗請到「設定 › VPN 通道」修復），不另放在 sheet 底部。
- VPN 通道失敗頁與設定 › VPN 通道的「連線說明」開同一頁（Figma R05）。
- 匯入 GPX 路線不可編輯：不顯示把手、刪除、新增停靠點或反轉。10 點以下以唯讀清單完整列出；超過 10 點時 sheet 顯示摘要＋折疊點位（起點、第 2 點、「中間 N 點」、終點），最後一列「查看全部 N 點」開唯讀可捲動清單，點列只在地圖定位該點（2026-10-20 決定，Figma D6／D7）。
- 「開啟 LocalDevVPN」在首次引導與設定 › VPN 通道行為一致：未安裝（`localdevvpn://` 無法開啟）時改開 LocalDevVPN 的 App Store 頁；App Store 也打不開才提示手動搜尋。兩入口已共用 `GoFlyExternalLinks`；系統拒絕 URL、App Store fallback 與實際安裝情況仍待真機驗證。
- 搜尋（地圖全螢幕搜尋與路線欄位搜尋）同時比對最愛地點的自訂標籤（label），例如輸入「公司」可找到標為「公司」的最愛地點；結果列以標籤為標題、地址為副標。
- 首次引導定位頁依權限狀態對齊 Figma R02／R03：尚未設定使用標題「允許 GoFly 使用定位」及「目前權限：尚未設定」，允許跳系統視窗且可略過；已允許使用標題「已允許使用定位」、狀態「目前權限：使用 App 期間 · 已允許」，主要按鈕改「下一步」，不跳視窗、不顯示略過；已拒絕顯示 warning、主要按鈕改「前往設定」，仍可略過。避免已允許時按鈕沒反應被誤以為壞掉。
- 設定子頁：定位權限（F4）、VPN 通道（F5）、背景執行（F6，含 F6.a 背景運行時間 sheet）、語言（F7）、外觀（F8）、裝置與簽名（F9）。語言與外觀各自為獨立設定子頁，點擊「語言」（F7）只顯示語言 options（跟隨系統、English、繁體中文、简体中文），不包含外觀選項；點擊「外觀」（F8）只顯示外觀 options（跟隨系統、淺色、深色），分開獨立顯示。
- GPX 匯入：「匯入 GPX 檔案」開系統檔案選擇器（GPX／XML、上限 2 MiB）；成功後新路線列在最上方並出現 snackbar（動作「載入」）；失敗以清單頂端 danger Toast UI（帶 ✕ 關閉按鈕）說明原因，原清單不變（Figma D8–D10）。
- 已匯入路線清單：點一下路線開底部動作選單：載入路線、查看全部點位、匯出路線、刪除路線（紅字）、取消；不使用左滑。「載入路線」帶到路線 tab；「查看全部點位」開唯讀清單；「匯出路線」開系統分享 sheet 分享原檔；刪除後 snackbar 可復原（Figma D11–D12）。
- 全螢幕頁、sheet 與執行模式面板的底部主要按鈕，下緣一律對齊距螢幕底 34 pt（home indicator 上方）；有 bottom bar 的畫面則在 bottom bar 上方。
- 搖桿在搖桿 tab 與漫步執行模式使用同一尺寸（150 pt）。
- 地圖右下角控制（2026-10-24 基礎規範，2026-10-26 路線模式更新）：
  - 瞬移與搖桿漫步模式：維持單一「回到定位」icon button（`Recenter` / `Dark · Recenter`，44 pt），不顯示圖層、指北或跟隨方向按鈕。按鈕固定在當下底部 panel 上緣上方 16 pt、距右緣 16 pt（x = 333 pt），隨 panel 高度移動；點「回到定位」將地圖方位重設為正北並置中模擬位置。
  - 路線模式（Section D，D1–D10.a）：依 2026-10-26 使用者確認，MapControls 在「回到定位」按鈕正上方（間距 8 pt）增設 1 顆 44 pt 圓形 icon button **`FitRoute`**（深色版為 `Dark · FitRoute`，圖示採 SF Symbol `arrow.up.left.and.arrow.down.right` 對角雙向展開箭頭），功能為「地圖鏡頭 pan 與 zoom 自動適配（fit）目前規劃或行進中路線」，使整條路線與起訖點完整進入可視範圍，且路線外框中心落在可視範圍（頂部列下緣到底部 panel 上緣之間）的中心（2026-10-26 使用者回報路線偏到畫面上方；已修正，尚未實機驗證）。MapControls 總高為 96 pt（FitRoute 44 pt + 8 pt 間距 + Recenter 44 pt），Recenter 維持距底部 panel 上緣 16 pt、FitRoute 位於其上方 8 pt，panel 伸縮時雙按鈕整組同步移動。Figma `04 · iOS Redesign` 淺深色 24 個含地圖之路線 frame 已全數同步完畢。
- Apple Maps 標誌與「法律」連結必須保持可見、可點擊：地圖 `layoutMargins.bottom` 隨底部面板、TabBar 與地點卡的上緣移動（另加 4 pt），不得被任何底部 chrome 覆蓋（`GoFlyMapAttributionUITests`）。
- 候選 Pin 上方的小型 Go 約 28 pt 高，點擊範圍至少 44 × 44 pt。
- 路線 sheet 右上「路線資料夾」按鈕使用資料夾類 icon（SF Symbol `folder`），不使用文件／`doc` 類 icon。
- 2026-10-23 路徑取得規則（使用者確認，取代步行優先與 50 公尺端點吸附限制）：選取地點保留名稱及 POI 座標；可執行路徑與地圖起終點使用 MapKit 實際回傳的道路入口，不補接地點中心，不設 POI 到道路端點的距離上限。每段依序嘗試汽車 → 行人 → 公共交通，取得有效路徑即停止；全部失敗顯示頂部「無法取得路徑」Toast。Apple SDK 的公共交通 `.transit` 僅支援 ETA，第三順位仍會嘗試，但不能宣稱可取得公共交通幾何路徑；不引入其他供應商。此行為沿用 D1 版面；Figma 線框未定義交通模式 fallback，依本次使用者確認補充。
- 路徑 Toast 的「重試」只重新取得目前輸入的路徑，不開始路線、不準備裝置或送出模擬位置。預覽與裝置連線分開，實際 Start 仍須符合既有裝置授權條件。已確認的起點／終點／途經點、順序或路線來源更新時，取消原預覽請求並忽略過期結果，立即規劃新輸入；以現有 Task 取消及版本比對處理，不另建競態框架。新鮮目前位置到達後可重試先前缺少位置的預覽。成功預覽按規劃輸入識別，Start 可重用道路端點與 POI 不同的路徑。
- 多停靠點保留各段道路頂點；下一段從上一段實際道路終點規劃，地圖途經點標示實際道路端點。若回傳路段仍不相連，視為沒有完整可執行路徑並顯示錯誤，不畫直線補接，也不跳接不相連路段。GPX 仍使用原始完整路徑，不套用交通模式 fallback。
- 本次路徑驗收：Taipei Station → Taipei 101 能取得並顯示汽車道路路徑，POI 與道路入口相差超過 50 公尺仍有效；汽車失敗才嘗試行人，再嘗試公共交通；全失敗顯示錯誤，Retry 僅重取，輸入更新後舊結果不覆蓋新路徑；Start 使用預覽的實際道路起點。共用規劃器保留供漫步後續接入，本次未改漫步。程式驗證：未簽署 iOS Debug 編譯通過；Mac 即時 MapKit 查詢第一順位汽車模式取得 Taipei Station → Taipei 101 共 64 個路線點、約 6.24 km，道路起點與 POI 相差約 115 m 仍可建立預覽；Retry 驗證維持 editing、準備裝置與送點皆為 0。本次尚未安裝／iOS 實機驗證。
- 路線規劃（D1，新增路線初始狀態；2026-10-24 使用者確認更新）：清單卡片採用白底細邊框卡片；起點預設為目前位置，無最後模擬位置與真實 GPS 時留空（「搜尋地點或輸入經緯度」placeholder）；目的地預設為空（「選擇目的地」placeholder）。2026-10-24 Figma D1／D2 更新後版面：清單卡 353 pt 寬、圓角 14 pt、0.5 pt `#C6C6C8` 細邊；每列 60 pt，左側 grip（`#C7C7CC`）、角色小標 12 pt Medium（起點／停靠點 N／終點）、地點 17 pt Regular，右側 ✕ 44 pt 命中。起點與終點常駐 ✕（清除後欄位保留、改為空值，不刪除端點列；空值時 ✕ 停用）；中途停靠點 ✕ 刪除整列。清除或刪除後不顯示 toast／snackbar（2026-10-26 使用者確認；Figma D9 未同步）。D2 的 ✕ 為中性灰（取代舊「停靠點紅色刪除 icon」）。第一次點擊欄位選取，第二次點擊同一欄位開啟 D5；改點其他欄位會先選取、再次點擊才開啟 D5。D4 Pin「確認」回填目前選中欄位，頂部搜尋列仍可直接開 D5。起點或目的地為空、路線未規劃完成或規劃失敗時，開始按鈕保持停用狀態（disabled）。Figma Light／Dark D1 的固定操作列已同步為「＋ 新增停靠點」與帶 22 pt Figma `View List Icon: list.and.chevron` 自訂向量（App asset `RouteList`，template 著色；`list.and.chevron` 不是 SF Symbol，`Image(systemName:)` 無法顯示）、無外框的「檢視路線」（英文 View）；App 點擊後開啟全螢幕可編輯路線清單，但該清單頁的 wireframe 尚未設計。D2 多停靠點狀態仍顯示「⇅ 反轉順序」。驗收：D1 淺深色均呈現相同的 View List 圖示與「檢視路線」標籤；D2 保留反轉順序。D1 不配置速度膠囊與來回按鈕（依 Figma D1 渲染畫面；速度只在 D6 與搖桿／漫步設定，見 D7）。D2 多停靠點時只有點位清單垂直捲動（最多可視 4 列），標題列、右上雙圖示、「＋ 新增停靠點」、「⇅ 反轉順序」與底部「開始」列固定於捲動容器外，避免與 sheet grabber 手勢衝突；面板右上角星號按鈕點選開啟「最愛路線清單」（D19，原 D14）；下方「開始」按鈕左側配置 56 × 56 pt 圓形收藏星號按鈕（依 Figma D1 `Button / icon / 最愛路線`：底色 `#EEEEF0`、無邊框；「開始」為 56 pt 高 capsule，停用時同底色、灰字與播放圖示；初始為空心 star，點擊開啟「新增最愛路線」sheet D20，原 D15，儲存後變為實心 star；已是最愛時再點擊開啟「編輯最愛」sheet（改標籤或於 sheet 內刪除），不直接刪除，2026-10-26 使用者指示）；開始按鈕維持 12 pt 間隔；開始按鈕下方提供 16 pt 安全間隔，避免緊貼底部導覽列；點位圖示依起點、中途點（編號圈）、終點區分。
- 最愛路線與全部地點（D19–D23，2026-10-30 以 Figma 04 渲染更新取代舊規格）：
  - D19 由 D1 面板右上星號開啟左滑全螢幕導覽頁；canvas 背景、頂列「路線」返回／置中「最愛路線」／右側「選取」。清單從左右 16 pt 開始，包在單一 card 中，列高 64 pt、末列不畫分隔線；每列顯示星號、自訂標籤、起訖與點位數，⋯ 開 D20。Figma 底部欄位文字為「搜尋最愛地點」，但 App 僅搜尋最愛路線；欄位尾端使用系統 UIPasteControl。FavoriteRouteRecord 未保存距離，畫面不假造距離值。
  - D20 是從 D19 編輯最愛開啟的半開 sheet；背景 Dim 40%，頂列只有「取消」與紅色「刪除」，下方顯示「路線標籤」、placeholder「路線名稱」、路線資訊卡與 primary「儲存」。初次顯示不彈鍵盤；欄位的清除圖示常駐。資訊卡至按鈕上方保留 40 pt，按鈕下方依使用者 2026-10-30 要求留 40 pt；這項 App 留白覆寫 Figma 原渲染，不改 Figma。
  - D21 顯示多選導覽列、選取勾圈、刪除（2）與搜尋欄。按 D22 刪除後剩餘清單判讀，正確狀態為選第 2、4 列；Figma D21 同時將第 5 列畫成勾選，但標題仍寫 2 項，記為渲染矛盾。
  - D22 刪除兩項後顯示「已刪除 2 項」及「復原」success snackbar，success 圖示為圓形 check；snackbar 懸浮於底部搜尋區上方，不推動清單。
  - D23 是 D1「檢視路線」推入的左滑全螢幕「全部地點」頁。共用返回／置中標題列；單一 card 顯示序號、地點與角色（起點／停靠點 N／終點），列高至少 46 pt，末列無分隔線，不顯示 grip 或刪除圖示；卡片下方為「＋ 新增停靠點」及「⇅ 反轉順序」。列點選沿用 App 現有選欄位／再次開 D5 行為，Figma 沒有 prototype 規格。
- 匯入 GPX（D11/D15，原 D5/D6，2026-10-23 Figma UI/UX 規格更新）：採用 iOS 原生 Modal Sheet 結構（`.presentationDragIndicator(.visible)`），頂部中央配置灰色 Sheet Grabber 橫線（36 × 5 pt，淺色 #C4C4C6、深色 #48484A，位於 y: 6 pt）；頂部 header 採居中標題「已匯入路線」（17 pt Semibold），左側配置「關閉」文字按鈕（x: 20, y: 22），全面移除舊版 Navigation push 風格之後退箭頭與「路線」標籤，且 Sheet 內不顯示 Status bar 與 Dynamic Island；已匯入清單包覆於單一白色圓角卡中，自 y: 76 pt 起算（與 D20 編輯 sheet 頂部邊距與垂直間隔完全一致）；副標顯示「起點 → 終點 · 距離 · N 點」，下方註記說明選單操作；點列開載入／查看全部點位／匯出／刪除選單；底部為「匯入 GPX 檔案」按鈕（D16，原 D8）。D15（原 D6，已載入 GPX 面板）規格更新：移除「匯入路線 · 不可編輯」副標題與 Km/速度摘要列，點位清單卡上移至 y: 68（與 D1 對齊）；面板右上補齊最愛星號與 GPX 資料夾雙圖示；點位清單卡下方新增帶圖示之「清空路線」文字按鈕（標準中性黑，非錯誤紅），點擊清空當前載入的 GPX 路徑；面板高度縮減至 467 pt。
- 搖桿面板（E1 / E2 / E1.a / E2.a / E5，2026-10-24 使用者佈局調整）：單一面板，無「設定起點」按鈕；搖桿盤外圍具備 N / E / S / W 方位文字與旋轉指示。漫步 UI 全面優化：
  - 頂部漫步列（Wander row）：左側維持純 icon style shuffle（20 × 20 pt），主標「漫步」（E1 待命）與「漫步中」（E2 / E1.a / E2.a 執行態）維持加大 20 pt Semibold（Title 3）；**全面刪除右側 Switch 開關**，改將「時速膠囊」（Speed chip「⏱ 25 ›」，寬 68 pt、高 36 pt、圓角 18 pt）直接整合至漫步列最右側（置右齊平），無副標題，亦移除舊版獨立「移動速度」列與分隔線。
  - 搖桿位置與間距統一：因移除舊版「移動速度」列，E1 與 E2 搖桿圓盤統一向上移動至 y: 88 pt，內部元件（Title 漫步列、搖桿、下方按鈕）之間距完全對齊一致：漫步列（下緣 y: 64 pt）至搖桿間距固定為 24 pt，搖桿（下緣 y: 238 pt）至下方按鈕間距固定為 24 pt。
  - 下方操作按鈕：E1 待命面板下方配置全寬膠囊按鈕「自動漫步」（`Button / primary / 自動漫步`，寬 353 pt、高 52 pt、圓角 26 pt，位於 y: 262 pt，與上方搖桿維持 24 pt 間距，下方距 TabBar 維持 36 pt 間隔；點擊立即啟動漫步進入 E2）；E2 執行面板下方對齊相同位置與間距配置 2 個操作按鈕（寬度各 170 pt、高度 52 pt、圓角 26 pt，間距 13 pt，位於 y: 262 pt）：左側次要按鈕「停止漫步」（`Button / secondary / 停止漫步`，點擊即停止漫步返回 E1 待命），右側主要按鈕「更換地點」（`Button / primary / 更換地點`，**隨機更換目的地：以目前時速約 10 分鐘距離的地點隨機挑選新的目的地並重新規劃漫步路線**；2026-10-24 使用者規格確認）。
  - E2 漫步執行模式上方深色指示卡（Top / 漫步指示）左側對齊 D6 配置實心導航箭頭（nav），顯示前往資訊與剩餘距離／時速；依 2026-10-24 使用者佈局調整，**全面移除頂部指示卡右側之更換圖示按鈕**，將「更換地點」操作完整收斂至底部面板之主要操作按鈕。搖桿操作移動之位置變更準備於背景靜默處理，不彈出 Preparing Panel，避免搖桿操作時面板頻繁閃爍。
- 漫步執行模式收合面板（E1.a / E2.a，2026-10-24 使用者佈局調整）：漫步執行模式之 sheet 收合狀態（E1.a 與 E2.a，淺色與深色同步完備）。畫面規格：上方指示卡（Top / 漫步指示，y: 58 pt）與狀態膠囊（StatusPill / 模擬中，y: 140 pt）完全對齊 E4 / E2 執行態規範，無浮動搜尋列；下方隱藏 TabBar（無 mode tab）；底部收合面板高度固定為 122 pt（y: 730 pt），內部配置頂部 Grabber（36 × 5 pt，y: 6 pt）與漫步列（Wander row，y: 20 pt，內含純 shuffle 圖示、加大 20 pt Semibold「漫步中」標題、**最右側刪除 Switch 改置入置右時速膠囊**「⏱ 25 ›」，無副標題）；地圖右下角 MapControls 固定單一「回到定位」圓鈕（44 × 44 pt，位於 y: 670 pt、x: 333 pt，完全保持距 panel 上緣 16 pt）。提供行進中最大的地圖可視區域。
- 設定移動時速（D7 / E3，原 D13 / E4，2026-10-24 規格確認）：只有路線運行中（D6 路線執行模式）或搖桿／漫步（E1/E2）才有設定時速的 pill button（Speed chip「⏱ 9 ›」）；D7 背景正式統一為 D6 路線執行模式（點擊 D6 控制列右側時速膠囊滑出半開 sheet，覆蓋 40% Dim overlay 遮罩，不使用未執行的 D1 作為背景）。含 Grabber、「設定移動速度」、目前時速、原生 Slider 與「完成設定」。4 檔快選膠囊正式統一為 步行 5／單車 25／機車 50／汽車 100（單位 km/h，預設 25；2026-10-26 起以扁平圓潤風格的彩色向量插圖取代系統 emoji（透明背景，橘紅＋深藍＋芥末黃，original 渲染），App 現有資產 `SpeedPresetWalk/Bicycle/Scooter/Car`，淺深色與選中狀態皆不需換圖；2026-10-28 Figma 將四款重繪為無描線實心色塊插圖，D7／E3 改用 `speed/*` master instance，App 資產尚未同步）；Slider 範圍 1–120 km/h。本規格正式取代過往 5/15/40/60 舊註解與過渡版 5/20/60/120 畫面，Figma 中 D7、E3、Dark D7、Dark E3 之 UI frame、說明文字與預設選取狀態已全數同步更新完成。點擊快選或滑桿即時連動路線預估時間或漫步行進時速。路線與搖桿／漫步共用同一份已保存的移動速度偏好（預設 25 km/h，App 重開後保留）；任一處修改即同步另一處（2026-10-24 使用者確認）。Figma 衝突記錄：D6、D6.a、D10 頂部卡仍寫「5 km/h」、Speed chip 為「9」，與 D7 目前時速 25 不一致，屬示意數值，實作以實際偏好值顯示。速度 chip CS 外觀依 2026-10-30 確認：Default 為 `color/surface/card`＋`color/line/border`；Light Selected 為 `color/surface/card`＋`color/icon/accent`，Dark Selected 為 `color/surface/control`＋`color/icon/accent`；Selected 數字使用 accent 文字。路線與搖桿／漫步共用已保存的 25 km/h 預設偏好。
- 設定漫步範圍（E2 km chip／E2.b，2026-11-01 使用者新增，Figma 04 Light／Dark 已新增 UI frame，App 尚未實作）：E2 漫步列在時速膠囊左側新增「範圍膠囊」（`Button / Range chip (km)`，⌖ 圖示＋數值「5」（不顯示單位文字，單位於 E2.b sheet 說明）＋chevron，高 36 pt、圓角 18 pt，樣式同時速膠囊，與其間距 8 pt）。點擊彈出半開 sheet E2.b（背景為 E2、40% Dim），含 Grabber、「設定漫步範圍」、「完成」、漫步半徑值、4 檔快選（0.5／5／20／100 km，無插圖、文字置中）、Slider（0.1–100 km）與「完成設定」。功能邏輯：自動漫步以漫步起點為圓心，只在此半徑內挑選目的地並規劃道路；最小 0.1 km、最大 100 km，預設 5 km（2026-11-01 使用者確認）；地圖以藍色虛線圓圈與 8% 淡藍填色顯示範圍。km chip 同時出現在 E1 待命與 E2 執行面板（Light／Dark，漫步列時速膠囊左側）；圖示為共用元件 `icon/radius`（0 · 共用元件（Icon），24 pt outlined 描邊、SCALE constraints）。E1、E2、E2.b 的地圖都以目前模擬位置箭頭為圓心顯示同一藍色虛線範圍圓圈（2 pt 虛線、8% 淡藍填色）；E1.a／E2.a 收合面板是否顯示 km chip 與範圍圈尚未設計，記錄為待確認。
- 最愛清單（C1/C3）與編輯最愛（C2）：C1 右上角操作鈕為圓圈勾選圖示（`checkmark.circle`）；預設星號為實心；多選模式（C3 / Dark C3，2026-10-24 規格確認）右上角為「全選」按鈕，每列左側為勾選圈按鈕，多選狀態下每列不顯示星號按鈕（不會有 star button），每列文字與分隔線起始位置靠齊勾選圈（x: 43 pt，淺色與深色完全對齊），右側「⋯」隱藏；深色模式（Dark mode）未選取勾選按鈕底色（`secondarySystemBackground` `#2C2C2E`）與邊框（`#8E8E93`）均與 App 黑色背景相異且具備明確對比，Dark 選取狀態使用深色表面與藍色勾記 `#0066CC`；底部刪除按鈕具備垃圾桶圖示與批次計數（`Button / dangerFill / 刪除（2）`，寬 361 pt、高 48 pt、圓角 24 pt），**移出 search field section，獨立浮動於 search field section 上方（y: 670 pt，距下方 y: 730 pt 搜尋欄頂部維持 12 pt 間距），與 D21 完全一致**；底部搜尋列為標準單一搜尋欄（y: 730 pt，高 122 pt），具頂部 0.5 pt 分隔線。2026-10-24 Figma 元件庫更新：`Dark · 0 · 共用元件（按鈕）` 收納 `Button / Check · Selected`（Dark 深色表面與藍色勾記 `#0066CC`，24×24 pt）與 `Dark · Check button / off`（次要背景底加灰色細邊，24×24 pt）共用元件；Dark C3（最愛地點多選）、Dark D21（最愛路線多選）與 Dark D22（最愛路線刪除復原）中已選取項目的勾選圈已全面改用 `Dark · Check button / on` 共用元件實例（修正原先 Dark D21/D22 誤用黑底圈導致暗色對比缺失之問題，統一為深色表面與藍色勾記規範）。C2（編輯最愛 sheet）下方為「儲存」主要按鈕、右上角為「刪除」文字按鈕、左上角為「取消」文字按鈕；地點 sheet 與地圖點選 Favorite 星號新增最愛時彈出 C2 編輯標籤，點「儲存」後才真正保存。
- 地點與搜尋（B4/B5，2026-10-23 使用者確認）：搜尋結果座標採 5 位小數且無星號圖示；地點選項左側圖示使用共用 `icon/pin`（不使用 SF Symbol `mappin.and.ellipse`）；全螢幕搜尋頁全面移除自明之「輸入地點或緯度、經度。」文字提示條；路線選點頁頂部 chip 標籤（如「選擇終點」badge）改為靠左對齊（置左），且空輸入清單中不再顯示「清空地點」或「在地圖上選擇」選項（2026-10-25 使用者確認移除後者），右側「最愛地點」文字按鈕使用 primary 文字色（不再用 secondary，避免看似 disabled）；App 現行地點選取／點地圖放 Pin（B5）使用獨立「地點卡」（LocationCard，寬 361 pt、固定高 188 pt、圓角 20 pt、雙層柔和陰影；與下方 Figma Route variant 的 361 × 180 pt 設計尺寸不同，App 尚待同步），覆蓋於底層 bottom bar 和 panel 上方（蓋在 bottom bar 與收合 panel 上面），不是取代 panel；底層 panel 維持收合狀態（呈現目前模擬位置與收藏／複製），bottom bar 亦維持在底層；地點卡右上角使用 B `Clear / Enabled / Large` 共用 icon button（44 × 44 pt，無底色／邊框），Close glyph 使用共用 `icon/close`，標題最多 1 行、地址最多 2 行並固定保留兩行空間，標題優先序為有效最愛標籤、地名、地址、經緯度（與瞬移收合面板位置標題共用 helper）；Light Figma `Light · LocationCard` 自 2026-10-28 僅保留 `Layout=Route`（361 × 180 pt、圓角 16 pt；文字 y=20／48／70、操作列 y=117–119），B5／B7／D4／E4 均使用此 variant；Floating 已刪除。內文左緣統一 16 pt；固定高度不隨內容增高，不因地址長短改變文字／按鈕錨點；座標列顯示經緯度與直線距離，下方橫排動作按鈕依 Light 共用 C／B variants 組裝：藍底白字 Go 置左、Star 與 Copy 純 icon 按鈕置右；卡片無邊框，fill 綁 `color/surface/overlay/card`（`#F9F9F9F2`，95% opacity），並使用 12 pt Background Blur；點擊「☆ 收藏」立即彈出 C2 編輯最愛 sheet 供使用者編輯標籤與保存；點擊 ✕ 關閉地點卡，保留底層原面板與 bottom bar 狀態。
- 首次啟動與引導（R01–R05、R07、R08；R06 無目前 Figma frame）：R01 畫面底使用 canvas，品牌圖框綁 Common Color `gray/50`（Light）／`gray/900`（Dark），標誌與名稱使用 primary 文字色，進度使用 primary 填滿 70% 與 `surface/control` 軌道。R02／R03 為置中定位引導，Figma 未顯示導航返回按鈕，App 隱藏導航列；Hero 圖示背景綁 Common Color `gray/50`（Light）／`gray/900`（Dark），不可替換為 theme `surface/control`。R03 已授權狀態使用標題「已允許使用定位」與 pill「目前權限：使用 App 期間・已允許」。Figma frame 的填色 `icon/location` 與共用 Icon 板唯一的線框 `icon/nav` 不一致；App 依共用 Icon 規則使用 `icon/nav`，此 glyph 差異列為 Figma 缺口，未自行建立資產。R04 依目前 04 渲染：canvas 背景、四列步驟 card（連上 Wi‑Fi／開啟 LocalDevVPN／點 Connect／點重新檢查）、連線說明入口、中間 StatusPill 及單一底部「檢查連線」主按鈕；步驟編號使用 Primary 藍色與白字。VPN 檢查錯誤由共用浮動 Toast 顯示，含「重試」動作，錯誤狀態膠囊為「連線錯誤」；底部錯誤狀態按鈕為「重新連線」（英文 `Reconnect`）。成功後 App 再次確認並直接進入 B1 收合 sheet，不顯示 success Toast；Figma R04 靜態檢查 CTA 保留。R05 依精簡渲染使用自訂「返回／連線說明」列、三列步驟卡及一張 troubleshooting 卡，沒有大標題、副標、逐步說明或底部按鈕；本機網路權限列移除後目前沒有替代直達設定入口，待產品決定。R07 Mac 配對頁：Common Color `gray/50`／`gray/900` 的 120 pt Hero 位於 x=136、y=190；28 pt Semibold 標題從 y=340 開始；15 pt 內文置中、寬 287 pt、y=392，繁中內容為「請使用 USB 傳輸線連接 Mac，並於 Mac 端 GoFly 完成裝置配對與簽名授權。」（不含「安裝 App 後」）；「尚未配對」StatusPill 位於 y=458。R08 顯示置中 gear Hero、28 pt Semibold 標題、15 pt 說明與底部「重試」按鈕。以上 A 區顏色、文字與版面以 Figma 04 最新渲染為準；票 06 的 Light／Dark App 截圖及差異記錄在 `.scratch/gofly-ios-figma04/issues/06-section-a-onboarding.md`。未做實機驗證。
- 設定首頁（F1）：導覽返回鍵改為與 R02 定位權限完全一致的圓形返回 icon button（`<`）；設定項目使用對齊 Figma 的專屬 Badge 圖示；定位權限狀態文案對齊 HIG 與 Figma「使用期間」（英文為「While Using」），行內居中排版，不發生多行折行跑版；背景執行標籤對齊「背景 App 重新整理」。
- 背景執行設定（F6 / F6.a，2026-10-26 使用者規格確認；2026-10-26 依 Figma 04 渲染畫面校正，App 已實作並通過 iOS Simulator build，未裝置驗證）：設定各子頁已移除不必要的小字說明（定位用途、背景說明、VPN 步驟、配對備註、重置通道提示），F6 與 F6.a 都不顯示說明小字。偏好設定 `backgroundRunSeconds`（預設 12 小時，範圍 1 分至 24 小時 59 分）驅動瞬移、路線來回、自動漫步之背景工作目標；背景時長倒數（2026-10-26 使用者確認，程式已實作並通過 core 測試，未裝置驗證）：只計算 App 在背景的時間；回到前景即取消倒數並歸零，模擬任務（瞬移維持、路線來回、漫步）繼續執行，前景再久也不會因時長到期而停止；下次進背景以當下設定重新倒數。因 iOS 只接受在前景提交 `BGContinuedProcessingTask`，回到前景時若上一段背景已計時，或在「設定 › 背景運行時間」關閉 sheet 後設定與已提交目標不同，會取消舊的背景工作並立即以當下設定提交新的（`MovementContinuationController.restartDurationCountdown`）；瞬移維持由 `PositionHoldController` 只在背景累計 ACK 時間，回前景歸零。背景中倒數到期仍依原規則暫停移動並提示「背景任務已完成」。
  - F6 · 設定 › 背景執行：第一群組兩列：「路線與漫步」（右側灰字「系統背景任務」）、「背景運行時間」（右側次要文字如「12 hr」／「30 min」／「12 hr 30 min」，三語都用 `hr`／`min`，加 chevron.right，點擊開 F6.a）。兩列間 0.5 pt 分隔線。第二群組獨立一張卡：「背景 App 重新整理」（右側狀態與 chevron，開 iPhone 系統設定）。群組下方沒有說明文字。
  - F6.a · 背景運行時間 sheet（高 336 pt）：Grabber；導覽列左「取消」（還原開啟時的值）、中標題「背景運行時間」17 pt Semibold、右「完成」17 pt Semibold；導覽列下 16 pt 為時間滾輪（2026-10-26 使用者指示移除「目前設定」卡，滾輪本身已顯示目前值）（353 × 130 pt、圓角 14、淺 `#F9F9FB`＋0.5 pt `#E5E5EA`／深 `#242426`＋`#38383B`），小時 0–24、分鐘 00–59 雙滾輪，中間灰色冒號，最少 1 分、最多 24 小時 59 分；數字列不重複帶單位，單位固定在各欄選取列旁，捲動時位置不變，僅選取列呈現單位（2026-10-26 使用者確認）；英文使用縮寫 `hr`／`min`，中文使用「小時」／「分鐘」。左右欄等寬，選取灰底以冒號為中心左右對稱；數字字級略大於一般欄位文字（iOS `title2`），單位固定在選取數字旁。滾輪下 40 pt 為 52 pt 全寬膠囊「完成設定」。沒有「上限 24:59」膠囊、快速選擇膠囊或說明小字（2026-10-26 取代先前文字規格）。滾輪使用系統 wheel picker，選取帶與列高由系統繪製，非 Figma 的 40 pt 自訂列。冒號依 `docs/IOS-TYPOGRAPHY.md` 用 `GoFlyFont.title`（20 pt）與 disabled 文字色；2026-10-26 使用者確認 App 依設計系統為準。
- 系統訊息與中斷恢復 UI（2026-10-23 / 2026-10-24 確認；B8/B9 panel 於 2026-10-26 依 Figma 04 渲染校正）：所有系統訊息（錯誤、背景中止、中斷等）一律不要加在 bottom sheet 或操作 panel 上面或裡面，全面改為獨立的 Toast UI 浮動於頂部搜尋列／top bar 下方（約 y: 136–156 pt，寬度 361 pt 居中）。瞬移中斷恢復（B8/B9，原 B8/B8.a）底層維持 B1 標準瞬移收合面板（120 pt），保留位置名稱、座標、收藏與複製，不顯示 Resume 按鈕；有新鮮真實 GPS 時標示「目前位置」（B8）並使用實心藍色 RealArrow，無新鮮真實 GPS 時標示「最後模擬位置」（B9，原 B8.a）並使用灰色箭頭。恢復操作只由獨立浮於搜尋列下方的 Warning Toast「重試」提供。地圖首頁未連接 Wi-Fi（B10，原 B7.a / R01.a）採 100% 實心 Danger Toast 提示。深色主題（Dark theme）之 B7、B8、B9、B10 一律與淺色主題完整對齊。
- 搖桿／漫步 Pin 與地點卡（2026-10-24 本輪已實作）：手動搖桿採 CandidatePin，Pin 與卡片同為「Go」，共用瞬移命令且成功後留在搖桿；漫步候選採與瞬移相同的 CandidatePin（2026-10-26 使用者指示，取代 DestPin）；App 現行 Pin 與卡片皆為「確認」並共用道路重規劃，從當前模擬位置沿道路到新目的地、不瞬移到終點；04 Figma 的 PinConfirm 保持「確認」，LocationCard CTA 已更新為共用 Go（App 尚未同步）。選點與已生效目的地分開，成功取得路線才替換。漫步地點卡出現時 panel 收至最小高度並保持，拖動 grabber 或搖桿 tab 可展開。
- E4 現稿讀回：底層122 pt收合面板、361×188 pt地點卡（y=636）、回定位鈕位於卡片上方16 pt（y=576）；原路線目的地與新候選分開，兩者均為空心 DestPin，候選 PinConfirm 為「確認」；04 Figma LocationCard CTA 現為共用 Go（App 尚未同步）。**2026-10-26 使用者指示已取代此稿的 Pin 樣式**：已生效目的地只畫路線終點粗圓點（不另疊 DestPin），候選改用瞬移 CandidatePin；Figma 04 已同步（2026-10-26，D／E 各幀與深色版改用 `MapNode / 目的地`，E4 候選改 CandidatePin）。最終截圖時修正 Light 缺候選 Pin、Dark 使用實心 CandidatePin 的差異，兩種主題修正後已重新截圖讀回。App 行為已接入並通過 iOS Simulator build。2026-10-27 Icon 目錄更新後，DestPin master 與目錄卡已刪除；E4 候選只使用 CandidatePin，已生效終點由 MapNode / 目的地表示。
- 自動道路漫步（2026-10-24 已實作）：無目前或最後模擬位置時，從目前地圖視野中心周邊有限選起點、按速度×600秒預算選點距離、自選目的地並規劃道路；起點必要定位須 ACK 才開始。規劃失敗顯示「無法規劃路線」與「重試」。Retry 優先使用最新有效模擬位置，其次目前位置，兩者皆無才自選起點；每次重選終點、重規劃，成功後開始。無直線 fallback。
- Section E 的 E1/E1.a/E2/E2.a/E3/E4/E5 淺深色靜態畫面已按票修正並以 Figma Console 讀回；E5 Dark 已改為與 Light 相同的恢復列及 tabs。逐 frame 證據、行為及驗收見[搖桿與漫步重構方案](JOYSTICK-WANDER-REFACTOR-PLAN.md)及逐票 tracker。
- 路線與漫步的模擬箭頭（SimArrow）方位修正：依當前模擬位置於路線上之切線角度即時計算方位並平滑旋轉（包含轉彎與來回模式順向／逆向切換，逆向時自動轉 180° 朝向起點），保持箭頭方位與模擬移動路線完全一致。
- 路線設定、執行與中斷面板（D1/D6/D6.a/D10，原 D1/D3/D4，2026-10-23 / 2026-10-24 使用者確認）：D1 路線規劃面板全面移除 Km / 速度摘要列，高度依 2026-10-24 Figma D1 為 369 pt（BottomSheet / 規劃路線，取代 429 pt），起訖端點具備即自動預算路徑，無法規劃時彈出頂部獨立 Toast warning（D8，原 D1.a error），Start 保持 disabled；支援 D3（原 D17）高度最窄收合（76 pt）。路線執行模式（D6，原 D3）下方面板包含完整進度列，控制列全面改為純圖示線框按鈕（Light 白底、Dark `#2C2C2E` 控制表面、0.5 pt 細邊框、微陰影，無文字標籤）：左側「來回」按鈕開啟為 `repeat`、關閉為 `repeat.slash`；「順向／逆向」按鈕改為垂直上下雙箭頭（順向左下淺右上深、逆向右上淺左下深），且僅在來回開啟時可切換，關閉時置灰；右側 Speed chip 取消 `km/h` 單位，僅呈現儀表圖示與純數字（如「9」）；點擊左下方「結束」按鈕直接終止行進並切回 D1 編輯模式、保留目前位置，不再彈出確認浮窗（2026-10-26 使用者指示，取代 D6.a）。任務中斷模式（D10，原 D4）面板自動切換為高度最窄 UI（76 pt），配置「繼續路線」主要按鈕，並由頂部 80 pt 暖琥珀 Warning Toast（按鈕「重試」）提示。
- 路線執行進度列標籤（D6／D6.a／D7／D10／D10.a 與深色版，2026-10-26 使用者確認；App 已實作，Figma 已同步，未裝置驗證）：前景只有單趟路線需要剩餘時間，進度條左側標籤（原「目前位置」位置）改顯示依目前時速估算的剩餘時間，無條件進位到分鐘：未滿 1 小時「剩餘 N 分」，1 小時以上「剩餘 H 小時 M 分」（en `N min left`／`H h M min left`、zh-Hans `剩余…`）；尚無進度時顯示「路線進度」。右側百分比不變。路線來回沒有終點，維持「目前路線位置」。執行中或暫停時改時速，剩餘時間立即依新時速重算（進度條標籤與頂部導航卡「約 N 分」同步），不必等下一步（2026-10-26 使用者確認，core 測試覆蓋）。 Grabber 下緣到進度標籤 20 pt（2026-10-26 使用者指示，原 11 pt）：執行面板頂端上移 9 pt、高度 +9 pt（D6 面板頂 y 625、Grabber y 631–636、標籤 y 656），其餘內容與按鈕位置不變，MapControls 同步上移 9 pt；App `executionPanel` 上內距 24 → 33 pt。
- 全螢幕搜尋（D5，原 D2，依 2026-10-30 當前 Figma 渲染更新）：路線欄位選點的搜尋欄採 focused 狀態，空 query 時不顯示 placeholder，保留游標、貼上鈕且不顯示清除鈕；下方灰底旗標 chip 顯示「正在選：終點」（起點／停靠點 N 同理），同行最右側配置 22 pt 空心星號與 `Favorite`（15 pt Medium），按鈕高度 44 pt、VoiceOver 名稱沿用 `favorites.shortTitle`。空 query 顯示「使用目前位置」及「最近搜尋」；輸入後改顯示搜尋結果。「最近搜尋」標題同行配置「清空記錄」按鈕；點任一結果立即回填選中路線地點並返回 D1。
- 背景持續不依賴定位權限：GoFly 只請求「使用 App 期間」，不要求「永遠」，也不顯示權限升級 sheet（2026-10-20 決定，取代原「非永遠時出現升級說明 sheet」條件）。
- 2026-10-23 最新背景規則取代不定長 ACK 計數（2026-10-26 規格更新為可自訂）：瞬移成功後維持同一座標、路線開啟來回及漫步，預設使用 1 小時工作百分比（可於「設定 › 背景執行」中自訂背景運行時間，上限 24 小時 59 分鐘，Figma F6 / F6.a）；單程路線使用已確認的實際路程比例，在目的地終點 ACK 後完成。瞬移維持每 5 秒重新確認同一座標，不能製造位移；時間進度只在 App 位於背景且成功 ACK 後增加，不計入前景時間與失效／暫停缺口；回到前景歸零並以當下設定重新提交背景工作（2026-10-26 更新）。達到設定時間至 100% 後完成背景任務、停止維持或暫停移動，不自動開下一個任務；後續必須由使用者明確操作。共用一個 `<Bundle ID>.movement`（Bundle ID 依簽署 Team ID 產生）（iOS 26 `BGContinuedProcessingTask`），採 `.queue` 等待名額，進度與任務標題須如實顯示。設定時間是工作目標，不是系統保證的背景時間，iOS 仍可提前中止。
- 系統拒絕、不支援或讓任務到期時，移動暫停；若路線因此暫停，回到前景以頂部獨立 warning Toast（高度 80 pt、實心不透明底、附白色「重試」動作按鈕與 ✕ 關閉，呼叫同一路線 Resume）提示使用者。其他背景執行提示維持原因與設定修復動作；前景執行中、系統尚未啟動背景任務時被拒絕，只提示、不中斷前景移動。背景任務到期原因須由裝置診斷記錄判讀；截圖或程式模擬不代表真機背景續行驗證。
- 瞬移維持暫停時顯示短文案「位置維持已暫停」及「重試」，只在可接受新 Go 時啟用；12 小時正常完成顯示「12 小時任務已完成」。session 暫時中斷時，在既有執行權內自動重建、重新核對身分並確認同一模擬座標；已失效而轉灰的箭頭需恢復的真實 ACK 才能還原，成功後接續剩餘工作。使用者 Stop、新操作交接或系統已收回執行權後，不得由舊重連重啟模擬；修復仍失敗或身分／配對問題沿用錯誤與明確 Stop 流程。
- 新增驗收：瞬移實際 ACK 才啟動固定維持；三種 12 小時模式百分比與真實時間／ACK 一致，12 小時上限停止且無自動續開；單程仍按路程到達完成；session 故障可在同一執行權內恢復同一座標，停止／到期與遲到 ACK 不得復活任務。離線時鐘與故障注入驗證、安裝／配對核對、真機長時間切至遊戲或 Google Maps 的定位效果須分開記錄。
- 2026-10-23 驗證狀態：build 28 已經正式 renew 安裝到指定 iPhone；安裝、配對匯入、裝置支援證據皆成功，5 項既有資料指紋不變。236 項 Swift Testing、58 項 XCTest、13 個原生服務故障情境及模擬器建置通過。12 小時完成邊界以虛擬時鐘驗證。build 28 真機瞬移測試由使用者回報外部 App 位置正常；診斷在台北時間 12:39:02–13:03:26 記錄 278 次固定位置定位 ACK 全部成功，最大間隔約 5.5 秒，其中 12:39:06–12:52:39 連續背景 13 分 33 秒；已確認約 24 分 24 秒的 ACK 維持，未宣稱連續背景 24 分鐘或 12 小時。期間未觸發 session 修復，故真機故障後自動恢復仍未驗證。
- 真機驗收分別覆蓋單程路線、來回路線與漫步：單程抵達目的地後應完成背景任務；來回跨過路線端點後仍應回報 ACK 進度；漫步在背景中應持續回報 ACK 進度。另驗證切到其他 App／鎖定螢幕與系統到期後的安全暫停及恢復。2026-10-22 裝置診斷確認：來回在背景約 102 秒回報 165 次 ACK，之後由 iOS 到期並暫停；漫步在背景約 30 秒回報 74 次 ACK，之後同樣到期並觸發安全暫停。2026-10-23 單程補測確認：GoFly 從 2026-10-22 23:55:37 至 2026-10-23 00:00:14 持續在背景執行，回報 440 次 ACK，最後達 99.9999% 後以 `reason=ended` 收尾，未見到期或取消；這與目的地完成後正常結束背景任務的路徑一致。已確認三種模式都能在背景送點；iOS 仍可能提前終止長時間的來回或漫步任務。

### 改版實作狀態（2026-10-20）

- 步驟 0 盤點：完成，清單在 `work/gofly-ios/redesign/INVENTORY.md`（`work/` 不進版控）。
- 步驟 1 共用元件：**已實作**（`GoFlyStatusBanner`、`GoFlySnackbar`、`GoFlyStatusPill`、三段式 `GoFlyBottomSheet`、`GoFlyBottomBar`、執行模式 header／controls 骨架、danger／warning／success token）。**模擬器已驗證**淺色、深色、Accessibility XXXL，截圖在 `work/gofly-ios/redesign/step-1/`。
- 步驟 2 主畫面骨架：**已實作**浮動搜尋列＋齒輪、狀態 pill、右側指北／置中、三段式 sheet 骨架、三個等寬 bottom tab；舊的頂部狀態卡與面板內膠囊模式列已移除。**模擬器已驗證**淺色、深色、Accessibility XXXL，截圖在 `work/gofly-ios/redesign/step-2/`。
- 步驟 3 搜尋與瞬移：**已實作**全螢幕搜尋、最愛標籤比對、地點 sheet、兩處 Go 與點圖最小避讓。最近搜尋為目前地圖 view 記憶體內最多 8 筆。
- 步驟 4 路線：**已實作**點結果即回填、資料夾入口、GPX 匯入／匯出／刪除復原、唯讀摘要與全部點位、路線執行模式。
- 步驟 5 搖桿／漫步：**已實作**共用 150 pt 搖桿、隨機目的地次要按鈕、漫步執行模式與結束確認；結束維持既有取消漫步語意，不清除最後模擬位置。
- 步驟 6 最愛：**已實作**星號延遲刪除／取消、編輯 sheet、多選、單次批次復原與最愛搜尋。
- 步驟 7 錯誤：**已實作**StatusBanner／snackbar 統一與修復指引，保留診斷資訊與既有命令可用性。
- 步驟 8 引導／設定：**已實作**Logo 啟動、延遲進度、定位三態、共用 VPN 說明及 URL fallback、語言與外觀子頁、診斷匯出保留。
- 步驟 9：最終建置、測試、代表性視覺抽樣及未完成項目，以 `work/gofly-ios/redesign/RESULT.md` 為準。僅新增兩個直接 Core 驗收案例（最愛批次復原、GPX 原始 bytes），調整既有基本 UI 測試，選取 3 個視覺樣本；不新增複雜或排列組合預防性測試。不將本節實作狀態視為逐條驗收通過。
- **尚待真機驗收**：本次 Bug Report 修正的冷啟動畫面、瞬移預設收合、B8/B9（原 B8/B8.a）GPS 分流、斷線狀態、Pin 可視位置、Location Card 與 C2 sheet 均未由程式修改推定為真機通過；GPS、VPN、背景任務、觸覺、VoiceOver 與裝置版面另見 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`；本輪未修改 Figma。箭頭方向 #15 與移動停止除錯仍分軌處理。


## iOS SwiftUI 逐頁視覺對齊（2026-10-20，第三輪）

本輪只修改 `app/GoFly/App/` 的 iOS Swift／SwiftUI 與相關字串，Figma「04 · iOS Redesign（Google Maps 參考）」只讀取作為對照；macOS App 不在本輪範圍。以下取代前文及前次交付中互相衝突的尺寸描述，功能及服務准入仍以原規格為準。

- 地圖搜尋列：50 pt 高、14 pt 連續圓角矩形、左右 16 pt；齒輪與清除在同列。狀態 pill 視覺高 30 pt，13 pt semibold；右側地圖按鈕為白／深色浮層而非一般內嵌灰底。
- Bottom bar：三等分、不加額外水平內距，標準內容列高 49 pt，底部使用實際 home safe area，頂部保留細分隔線。地圖控制依實測 tab bar 高度維持距 sheet 上方 16 pt。
- Bottom sheet：收合 116 pt；半開以完整可用垂直區域的 50% 計算，不在扣完地圖保留區後再縮一次。展開保留搜尋列與至少 96 pt 地圖區；短內容貼合自身高度，非瞬移面板不套用上次瞬移內容量測。每次 App 啟動進入地圖時沿用上次關閉的 mode，並將該模式的 panel 重設為正常內容高度（瞬移 B2、路線 D1、搖桿 E1）；B1／D3／E1.a 等最小高度只在使用者收合後呈現。Grabber 統一規格（2026-10-26 使用者指示，取代各模式 12／24 pt 與 6 pt 距頂）：膠囊 36 × 5 pt 距 sheet 頂 8 pt，膠囊下緣到第一列內容一律 20 pt（grabber 列共 33 pt），瞬移、路線、搖桿／漫步與執行面板相同；操作區 72 × 44 pt 不占用額外內容高度。App 以 `GoFlyGrabber` 常數實作；收合最小高度非瞬移 96 pt（原 76）、搖桿展開 349 pt、瞬移展開 305 pt。Figma 04 頁 D1–D10、B1–B11、E1–E5 與深色版 grabber 已同步為 y 8、內容 y 33（各 frame 高度相應增加）；iOS 系統 sheet（C2、C20/D20、D7/E3 設定時速、F6.a、D11）的 grabber 由系統繪製，維持各自 Figma 規格，未套用此規則；本次啟動 detent 改動未裝置驗證。
- 瞬移首頁半開也呈現「目前模擬位置」摘要、收藏與複製，摘要後接分隔線與最愛地點（依 2026-10-23 最新 Figma 稿件 B2 移除最近使用區塊，半開保留前 2 筆最愛＋「查看全部」；目前位置與最愛列左側星號皆為獨立按鈕（最愛列 44 pt 命中），點擊只開啟「編輯最愛」sheet（C2），已收藏時右上顯示「刪除」按鈕；點擊刪除按鈕才移除最愛，星號本身不刪除、不選取地點；點列其餘區域才選取地點（2026-10-26 使用者確認；Figma variant 待同步，未裝置驗證）；Figma B2 以 328 pt 為視覺參考，2026-10-23 實機回饋後改為依目前內容高度加 grabber 列（33 pt）自適應，以上下可用畫面為限，不再鎖定 328 pt；保持收合／半開兩種內容，使用拖曳把手調整，不加入 panel ScrollView 以免手勢衝突；右側地圖控制圓鈕維持距實際 sheet 上方 16 pt）。瞬移收合面板與地點卡共用標題 helper：有效最愛標籤優先，其次用地名、地址、經緯度；未知位置沿用已知最愛或最近地點資料，無資料時顯示座標，不為裝飾新增定位或反向地理編碼。地點詳情避免內外雙重 16 pt 內距，改用單層左右 20 pt、標題 22 pt、地址 15 pt、座標 13 pt，Go 顯示播放圖示。
- 搜尋／最愛：列表列高至少 64 pt，36 pt 圓形圖示，副標 13 pt、分隔線從文字起點內縮；搜尋輸入高 50 pt。最愛頁全螢幕顯示，返回與多選分開；多選標題反映數量，批次刪除為 danger CTA。編輯最愛採緊湊底部 sheet，標籤輸入、地址／座標資訊卡與底部刪除動作分層，大字級可展開捲動。
- 路線／GPX：左右 20 pt、節點列標準 60 pt、匯入路線列至少 63 pt、點位列採緊湊唯讀清單；執行模式的目的地圖示卡、進度與結束／暫停動作對齊稿件，操作仍由原 controller 管理。
- 搖桿／漫步：150 pt 搖桿；Light 凸起握柄白色，Dark 使用 `#3A3A3C` 控制表面與 `#98989D` 握柄前景；速度與漫步列、分隔線、目的地／換一個動作使用同一版面節奏；沒有起點時仍顯示真實不可操作狀態。
- 設定首頁依 F1 分為「權限與連線」（定位／VPN／背景）、「偏好」（語言／外觀）與「裝置」；語言、外觀列都開啟同一原生 Picker 子頁，不把 F7 的討論選項清單當成自訂控制。說明入口保留。
- 引導、VPN 說明及設定子頁逐張對照 R01–R05、F1、F4–F9；F2／F3 是設計規則參考，不新增為 App 頁面。系統檔案選擇器、分享視窗及系統授權使用原生介面。

驗收：除既有互動測試外，檢查淺色、深色、Accessibility XXXL 的主要頁面截圖，新增最愛編輯／多選與六個設定子頁的截圖覆蓋。逐頁證據及仍有差距記錄於 `work/gofly-ios/precision/RESULT.md`。程式已調整、模擬器已驗證與待真機結果分開記錄，不以建置通過代替視覺或裝置驗收。

本輪深色層次修正：`surface` 保留全螢幕頁面的 systemBackground（黑色）；新增 `cardSurface` 對應 secondarySystemGroupedBackground（淺色白、深色 #1C1C1E），用於地圖搜尋列、sheet、浮動控制、狀態 pill 與內容卡。`secondarySurface` 對應 tertiarySystemGroupedBackground，深色內嵌控制為 #2C2C2E。主 CTA 的文字仍依 `surface` 反轉，不混用卡片底色。地圖控制間距按量測值扣回 home safe area，避免重複計入 34 pt。執行指示卡由既有進度顯示剩餘距離／預估時間／速度；來回路線顯示任務狀態及速度，不假設固定完成終點。

## 2026-10-23 實機回饋後修正（程式與裝置驗證分開）

- 共用狀態（2026-10-24 使用者更新）：地圖 Status Pill 與設定服務 Pill 均讀取三模式共用的 session display state，固定使用「啟動（灰）、模擬中（綠）、暫停（黃）、停止（灰）、錯誤（紅）」。前四態均有連線 session；自動探測 pending 不覆寫最後已知連線與任務狀態，已知斷線重試期間保留紅色狀態，成功後自動續行斷線前仍在執行、未被使用者暫停／停止且仍有有效執行資格的原任務；探測成功不能冒充定位 ACK。取消、配對、身分及裝置準備錯誤保留原原因提示，不冒充斷線；不新增「受限／準備中」pill。此為需求更新，尚未實作／實機驗證。
- 前景補檢：啟動、回前景時提出靜默檢查需求；舊 probe 取消尚未返回或 native busy 時保留 pending，排空後在 active scene 補做，不重疊 probe。此處「背景檢查」是 App 內非同步檢查，不宣稱 iOS 背景無限執行。
- Go 恢復：沿用 NativeDeviceService session manager 的一次重建／同座標修復，移除瞬移外層的多輪 preparation retry，避免一次 Go 疊加重試。既有 dispatch gate、Stop 與不確定操作限制仍適用，UI 不另行重送。
- 瞬移成功／複製 Toast：有地點卡時（瞬移／搖桿／漫步／路線選點）固定浮在地點卡上緣上方 8 pt（卡高固定 188 pt，不依量測值；2026-10-26 使用者最新指示，取代 20 pt）；瞬移收合面板的 Copy Toast 與 panel 上緣相距 8 pt（取代原 6 pt）；不重複加底部 safe area，不更動路線面板、漫步 Toast 定位。此版依使用者明確間距要求實作；Figma Desktop Bridge 未連線，渲染稿尚未同步／核對。
- 編輯最愛：僅名稱輸入框背景改為較淺的語意灰底（淺色 systemGray6／深色 systemGray4），保持可編輯、焦點邊框與清除按鈕。
- 視覺依據：已讀取目前 iOS redesign B5（121:51730）、C2（121:52228）及 B2（121:51416）；兩行地址、內容自適應面板、8 pt Toast 間距及較淺輸入框是使用者確認的後續修訂；本次無法連線 Figma Desktop Bridge，Toast 間距尚未同步至渲染稿。
- 驗收：冷啟動待命→探測結果、快速前背景補檢、兩頁 Pill 一致、Go 最多一次 session 修復；短／長地址卡片錨點、地點卡與瞬移面板 Copy Snackbar 的 8 pt 間距、面板拖曳與大字級自適應、最愛輸入框淺／深色仍待本次修正後裝置驗證。

## 2026-10-24 三模式 session pill 五態規格（使用者確認、Figma 已完成、App 待實作與實機驗收）

| 文字 | 語意色 | 連線與任務 |
| --- | --- | --- |
| 啟動 | 灰 | 已有連線 session，尚未開始模擬 |
| 模擬中 | 綠 | 已有連線 session，執行模擬 |
| 暫停 | 黃 | 已有連線 session，任務暫停 |
| 停止 | 灰 | 已有連線 session，任務停止 |
| 錯誤 | 紅 | 存在任務、連線、服務或資料錯誤；原因另行顯示 |

此規則同時適用瞬移／固定定位、路線、搖桿（含漫步）及設定服務 pill。取代舊「服務待命／執行中／已暫停／受限」用詞；正常探測與送點 pending 不產生「檢查中／準備中」第六態。詳細檢查進度、非連線錯誤及初始化狀態可於既有詳情／提示表達。設定「停止」在同一次操作中結束移動並清除模擬定位、關閉定位 session（2026-10-25 使用者確認，取代「停止仍保有 session」）；之後再瞬移或開始路線會重新建立 session。VPN 通道連線狀態另行判斷，停止仍不能當成 disconnect。連線狀態與箭頭位置可信度分開；探測成功不代表定位 ACK；斷線前正在執行且未被使用者暫停／停止的有效任務，連線恢復後應自動續行。使用者暫停或停止的任務不得自動恢復，連線造成的中斷與使用者暫停須分開判定。

Figma 設計更新進度（2026-10-24 完成）：
- `0 · 共用元件（正式版 token）`（淺色與深色元件板）已完整建立 5 顆標準 StatusPill：`啟動(灰)`、`模擬中(綠)`、`暫停(黃)`、`停止(灰)`、`錯誤(紅)`。
- `F1 · 設定首頁` 裝置服務卡 pill 已改為標準 status pill UI（`StatusPill / 啟動` 灰點，移除舊版淡綠底色，對齊 0 區規範）。
- `F3 · 規則參考 · 狀態與錯誤呈現` 之 Toast UI（danger、warn、success）與 Snackbar 已全面對齊 `0 · 共用元件` 標準（寬度 361 pt、居中浮動 x: 16 pt、條列筆記垂直間距修復無重疊）。
- `0 · 共用元件（正式版 token）` 的 `STATUS · BANNER / SNACKBAR / PILL` 原元件（Toast danger/warn/success、Snackbar 2 秒/可復原、StatusPill 5 態，淺深共 20 個元件）已全面設定標準 Auto Layout 與邊緣 padding：
  - Toast：水平 Auto Layout（固定寬度 361 pt、高度 Hug 依文字內容自適應；左右 padding 14 pt、上下 padding 12 pt、元素間距 10 pt；內部標題與說明垂直欄位間距 2 pt 自動折行）；邊線（strokes 1 pt inside）直接設定於元件本體並移除舊版固定尺寸之獨立 `border` 框架，使邊線與底色長寬 100% 同步完全對齊，徹底根除跑版。
  - Snackbar：水平 Auto Layout（固定寬 361 pt、高 52 pt；左右 padding 14 pt／帶按鈕右 padding 12 pt、上下 padding 10 pt、元素間距 10 pt、圓角 14 pt，垂直居中）。
  - StatusPill：水平 Auto Layout（固定高度 30 pt；左右 padding 12 pt、上下 padding 6 pt、圓點與文字間距 6 pt、圓角 15 pt，水平垂直居中對齊）。

驗收：三模式與設定頁五態文字及語意色一致；啟動、模擬中、暫停、停止時核對 session 仍存在；正常週期刷新不跳態；已知斷線重試保留紅色，真正恢復連線才解除；停止後晚到 ACK 不重啟模擬。文字／狀態搭配表達，不只依靠顏色。此處 Figma 設計已交付，程式實作與真機驗收待後續執行。

## 2026-10-24 三模式斷線自動續行與路線／漫步補間（使用者確認、待實作）

- 三模式採同一恢復協調：連線中斷期間 pill 持續紅色「錯誤」；重連成功後，若原任務在斷線前正在執行、未被使用者暫停／停止，且任務身分與執行資格仍有效，應自動續行。任務運行中確認斷線即自動 reset tunnel、重建並核對 session，不只等待探測恢復；須取得有效定位 ACK 才恢復正常模擬位置外觀與綠色「模擬中」；恢復失敗如實顯示原因。
- 使用者暫停／停止，包括在斷線重試期間操作，優先於自動恢復；完成、取消、新任務取代、冷啟動歷史或背景執行資格已被撤銷均不得由舊重連復活。不得重播已釋放的搖桿手勢。沿用原任務座標／路線／目標、方向及最後確認進度，不重設進度、不重複計數，每個任務至多一個恢復流程；不得由 UI 刷新直接重送。
- 路線與漫步每次正常 GPS 模擬位置更新必須有位置補間及最短角度平滑轉向。新 ACK 從目前可見位置接續至最新確認位置；路線沿已確認路段幾何補間、不在轉彎切角，漫步依實際移動路徑／步進資訊補間。正常 pending、健康探測與 pill 更新不反覆打斷動畫或改變透明度；動畫不推進到尚未 ACK 的目標，也不回寫核心位置或進度。
- 首次位置、瞬移大幅跳點、停止、clear、失去確認或 owner／epoch 切換時中止舊動畫，避免沿用無效路徑；固定定位同座標補送不製造位移。Reduce Motion 沿用系統偏好。
- 驗收：三模式執行中斷線後可自動續行，使用者暫停／停止與重連完成交錯時不復活；路線與漫步在正常、延遲、連續 ACK 下均平滑且不跳回／切角，停止及故障立即終止舊動畫。此更新取代先前「連線成功不自動恢復任務」的方案語意；尚未由文件更新推定程式或實機通過，未新增 Figma prototype。

## 2026-10-24 自動連線檢查間隔更新（待實作）

三模式共用自動連線探測由 2 秒改為 5 秒，以上輪完成時間計算，包含已斷線時的週期重試。首次／回前景與手動檢查仍在符合原有資格時立即排程；不重疊探測，忙碌或資格不符維持延後。只調整探測間隔，不改定位更新、固定位置補送、探測 timeout、ACK 期限或動畫頻率。送點回報的故障立即處理，不等下次輪詢。輪詢偵測斷線／恢復的等待窗口增加約 3 秒，總時間另含探測耗時與資格延後，不保證 5 秒內完成。

驗收：虛擬時鐘驗證上輪完成後 2 秒無新探測、5 秒後符合資格才開始；前景／手動立即排程及 max-one 限制正確；忙碌結束能重新排程；三模式五態與自動續行維持前述契約。此為規格更新，尚未實作或實機驗證。

## 2026-10-24 任務運行中自動 reset tunnel 與重建 session（使用者確認、待實作）

三模式有效任務執行中確認斷線，主動關閉舊送點資格、保存原任務與最後確認進度，等待舊 native 工作收束，再依序 reset tunnel、重建並核對 session、重新確認原任務位置，接續任務。固定定位保持同座標，路線保持原路程與方向，漫步保持原目標及速度；不重設進度、不重複計數或重播未確認操作。正常健康探測 pending 不觸發 reset，送點已確認故障不等待下輪 5 秒探測才修復。

恢復期間持續紅色「錯誤」與未確認箭頭；reset、probe 或 session prepare 單獨成功不代表模擬恢復，續行原任務取得有效定位 ACK 才顯示綠色「模擬中」與正常箭頭。使用者暫停／停止、新任務取代、完成／取消或背景資格撤銷均阻止自動續行；沿用既有生命週期與取消機制，在正常流程的必要邊界處理。已開始且不可取消的 physical reset 安全收束後不得自行恢復被取消的任務。

共用核心恢復協調負責序列化與有效 session／lease 交接；不能由 UI timer 呼叫手動 reset 或直接移除既有安全條件。每任務至多一個恢復流程，manual／automatic reset 不重疊。方案建議一次斷線至多一輪完整自動修復，失敗保留錯誤及重試入口，5 秒 probe 不反覆 reset；此上限為待確認的實作策略。結果未知的 native 呼叫維持未決，不因邏輯 timeout 假稱已結束。

驗收：三模式經正常 App 操作確認 reset → session 重建 → 位置 ACK → 原任務續行的順序；另驗實際可發生的服務修復失敗／逾時，以及修復期間使用者暫停／停止，確認不重複修復或繼續已取消的任務。不做每階段全組合故障注入。此為本次使用者確認的自動修復需求，取代只靠探測成功後續行的流程；App 及真機結果待驗證。

## 2026-10-24 實作與測試限於正常 App 操作（使用者補充）

本次刷新與恢復優化僅新增正常 App 操作路徑所需的判斷及測試。保留三模式啟動／執行／暫停／停止、模式及前後景切換、斷線／服務逾時／修復失敗與修復期間使用者取消等實際情境；受控時鐘及服務替身僅用於重現這些情境。不新增 UI 不可達狀態、繞過正常呼叫流程、偽造身分／內部狀態、任意回呼排列等防禦分支與測試，不擴張為全組合故障注入或無關壓力測試。沿用既有生命週期及取消機制，避免另造重複防禦狀態機；既有無關程式及測試維持原狀。此限制取代上述較廣的測試範圍描述，尚未開始 App 實作。

## 2026-10-24 模式切換的正常操作前提（使用者補充）

正常切換模式前，原路線或漫步已暫停。共用 status pill、箭頭刷新及自動恢復方案以此為前提；不新增執行中跨模式搶占、多 owner 競爭或新舊任務交錯的防禦邏輯與測試。驗收僅按「暫停路線／漫步 → 切換模式 → 切回」正常路徑，原任務維持暫停，使用者明確繼續才續行。這不是執行中斷線的自動續行情境。

保留修復期間使用者按暫停／停止時取消自動續行，以及既有服務呼叫序列化等正常流程所需處理；不為模式切換另造競態狀態機或全組合測試。此補充限縮前述模式／任務交接驗收範圍，既有無關邊界與測試不另行改動。目前為規格與方案更新，未實作或實機驗證。

### 2026-10-24 五態英文文案（使用者確認）

| 繁體中文 | English | 語意色 |
| --- | --- | --- |
| 啟動 | Standby | 灰 |
| 模擬中 | Running | 綠 |
| 暫停 | Paused | 黃 |
| 停止 | Stopped | 灰 |
| 錯誤 | Error | 紅 |

英文 Error 與繁體中文「錯誤」涵蓋所有共用狀態錯誤，不只連線中斷；具體原因保留各錯誤文案。英文 Standby 是「啟動」這一態的翻譯，不恢復舊 standby 判斷；Running 是「模擬中」翻譯，不另設第六態。舊 limited、preparing 等 pill 狀態及多餘文案 key 移除，任務控制器內的執行階段維持原用途。

### 2026-10-24 最終 Error 定義（使用者確認，取代較早的連線專用定義）

第五態統一為「錯誤／Error」（紅），泛指共用狀態中的所有錯誤。涵蓋 Wi-Fi／通道探測、原生裝置／session、路線規劃／匯入執行、搖桿／漫步、session 復原資料、最愛地點、匯入路線與最愛路線資料錯誤。正常使用者取消、健康探測 pending、正常定位 ACK pending、暫停與停止本身不是錯誤；首次未知也不能推定失敗。Error 優先於其他四態，原因保留原有具體提示，不以「連線中斷」冒稱所有錯誤。取消顯示某個 toast 不清除仍存在的底層錯誤或 blocked 資料狀態；正常修復／成功操作清除錯誤後再依任務階段顯示其餘四態。

此規則覆蓋本文先前「只有連線中斷才紅色」及「Error 只代表連線」的舊描述，未改變任務錯誤的實際處理或新增防禦性測試。搜尋輸入驗證與未進入共用狀態的局部編輯提示仍在原欄位顯示，沒有新增第六種 pill。完整狀態錯誤清單另見本次實作報告。

完整錯誤來源、代碼與文案見 [iOS Status Pill 錯誤清單](IOS-STATUS-ERRORS.md)。

## 2026-10-24 本次刷新優化實作狀態

三模式共用五態（啟動/Standby、模擬中/Running、暫停/Paused、停止/Stopped、錯誤/Error）、5秒探測、運行中自動重建tunnel/session續行、正常pending箭頭穩定、路線／漫步補間，以及路線按實際變更重繪，已在工作樹完成實作。Error涵蓋全部共用狀態錯誤，目錄見[77項錯誤清單](IOS-STATUS-ERRORS.md)。舊limited與額外pill文案已移除。

軟體檢查包含252項核心、15項連線及13個原生邊界情境，模擬器與未簽署iPhone建置通過；正常使用者暫停／停止、失敗Retry及timeout有對應驗證。真機畫面、外部App定位與故障恢復仍待集中驗收。未提交、不代表已安裝。Figma即時連線不可用，本次未更動Figma，最新泛用「錯誤/Error」第五態仍待同步；前文較早「待實作」紀錄以本節針對本次範圍的狀態為準，其他UI工作不因此宣告完成。

## 2026-10-24 共用元件規格（Figma `0 · 共用元件（正式版 token）`，Route Mode 開發準據）

D · 路線 section 已大幅更新並改用以下共用元件實例；路線頁面須以元件規格實作，不逐頁自行配色。數值取自 Figma Desktop Bridge 讀回；程式對應與差異見 [Route Mode 任務清單](ROUTE-MODE-TASKS.md)。

| Figma 元件 | 規格 | App 對應 |
| :-- | :-- | :-- |
| `Toast / 系統訊息 / danger｜warn｜success` | 361 pt 寬、高度隨內容、圓角 14、內距 12／14、元素間距 8；Light／Dark 底色使用各狀態 surface token。danger／warning 使用 22 pt outline alert icon，success 使用 22 pt outline check-circle；標題 15 pt `Theme/subheadlineEmphasis`、說明 13 pt `Theme/footnote`，文字走 primary／secondary token（Dark 說明小字與 X 均改用 primary）；動作為 56 × 32 pt 膠囊，邊線走狀態 token；✕ 視覺尺寸 20 pt，44 × 44 pt 命中區。Success 外框與圖示使用 `color/icon/success`（Dark `#6FC48B`），與 `color/line/status/success`（Dark `#52A072`）不同；依共用元件實際綁定及渲染採用 icon token | `GoFlyStatusBanner`（已合併 `GoFlyWarningToast`） |
| `Snackbar / 2 秒自動消失` | 361 × 52 pt、圓角 14、內距 10／14、24 pt success icon、訊息 15 pt `Theme/subheadline`；Light `surface/card #FBFBFD`／`line/border #C7C7CC`，Dark `surface/card #1A1A1C`／`line/border #636366`；文字為 Theme primary；兩主題皆使用兩層 floating shadow（9% y5 blur24、6% y1 blur3） | `GoFlySnackbar` |
| `Snackbar / 可復原` | 與同主題自動消失款相同底色、邊線、尺寸及兩層陰影；右側「復原」action 使用 56 × 32 pt 膠囊，Light 為 card 底、Dark 透明底，邊線與文字依 shared status-action tokens；約 5 秒 | `GoFlySnackbar`（含 action） |
| `StatusPill / 啟動｜模擬中｜暫停｜連線中斷` | 高 30 pt、圓角 15；Light `surface/card #FBFBFD`／Dark `surface/card #1A1A1C`，`line/border` 1 pt；8 pt 狀態點依 neutral／success／warning／danger icon token 著色；13 pt `Theme/footnoteEmphasis`，水平內距 16 pt、點與文字間距 6 pt；除連線中斷外使用 floating shadow。地圖 SearchBar 與 StatusPill 垂直間距統一 12 pt（execution header 與 pill 同值，符合 4 pt 間距規則） | `GoFlyStatusPill`、`GoFlyMapView.topBar` |
| `Button / Icon`（04 Light／Dark 共用元件板） | Light `Type=Standard` 的視覺尺寸為 Large `44 × 44`、Medium `40 × 40`、Small `36 × 36`、Extra Small `32 × 32` pt，圖示依序為 22／20／18／16 pt。Enabled 使用 `color/surface/control/floating` 底及 0.5 pt `color/line/separator` 邊；Disabled 使用 `color/surface/disabled`／`color/icon/disabled` 且無邊。Standard 圖示是 04 `0 · 共用元件（Icon）` 的可替換 instance。尺寸、觸控範圍與 Dark 樣式依各自元件規格；D1 Favorite 保留獨立控制。App 共用角色由 `GoFlyStyle.iconButtonSurface`／`iconButtonBorder` 指向 Figma tokens | `GoFlyThemeColor`、`GoFlyIconStyle`、`goFlyIconButtonChrome` |
| `SearchBar / 浮動` | 整體 361 × 50 pt；Light 輸入卡維持 301 × 50 pt。Dark 輸入卡直接使用 E `Text Field / Neutral / Icon + Text / Default` instance，301 × 48 pt、y=1；底色、邊框、14 pt 圓角、18 pt 搜尋 icon 與 15 pt `Theme/subheadline` 由 E 元件提供。Dark 貼上 icon 使用 Icon 目錄 `icon/paste`（18 pt，`color/icon/input/default`）置於 44 pt 無底命中區；Light／Dark Settings 使用 48 × 48 pt `Button / Icon` variant，22 pt gear 置中，與 48 pt 高的輸入框對齊；其 50 × 50 pt 外框與輸入卡間距 10 pt | 地圖頂部搜尋列 |
| `SearchField / focused｜normal` | 361 × 48 pt；Dark focused／normal 分別直接使用 E `Text Field / Neutral / Icon + Text / Focused`／`Default` instance，提供共用 surface、border、搜尋 icon、caret 與 15 pt `Theme/subheadline`。focused 保留 44 pt `Button / Icon` Clear；normal 右側為 Icon 目錄 `icon/paste`（18 pt，`color/icon/input/default`）與 44 pt 無底命中區 | `GoFlySearchPanel`、路線節點列 |
| `Slider / 原生黑白`、`Progress` | Slider 使用原生 4 pt 軌道及 28 pt thumb；Progress 6 pt、圓角 3，track 使用 `color/surface/control`（Light `#DEDEE4`／Dark `#2C2C2F`），value 使用主題 primary token | 原生 `Slider`、`ProgressView`；Switch 已不在目前 UI 使用範圍 |
| checkbox（圓形） | on：Light 24 pt 黑色實心圓＋白勾；Dark 深色表面與 `#0066CC` 勾記（`Dark · Check button / on`）；off：22 pt 圓、1.5 pt `#C7C7CC` 邊（深色 `#2C2C2E` 底＋`#8E8E93` 邊） | `GoFlyCheckboxIcon` |
| `TabBar / 瞬移・路線・搖桿（等寬）` | variants `Mode=瞬移｜路線｜搖桿`；393 × 83 pt、`#F9F9F9` 96% 底＋頂部 `#C6C6C8` 細線；每格 131 × 49 pt、25 pt 圖示；選中黑色 2.29 pt 線條＋10 pt 黑字，未選 1.875 pt `#999999`＋10 pt Medium | `GoFlyBottomBar`、`GoFlyTabIcon` |

移動速度（D7）：快選 5／25／50／100（向量 icon：步行／單車／機車／汽車，非 emoji）、Slider 1–120、預設 25；chip 預設態使用 `color/surface/card` 填色與 `color/line/border` 描邊；Light 選取態使用 `color/surface/card` 填色、`color/icon/accent` 描邊與 accent 數字；Dark 選取態使用 `color/surface/control` 填色、`color/icon/accent` 描邊與 accent 數字。路線、搖桿與漫步共用同一個偏好（`GoFlyPreferences.movementSpeed`，由 `MovementSpeedSynchronizer` 同步），重開 App 保留。

按鈕英文字：所有按鈕的英文文案只用一個單字（如 Resume、End、Add、View、Clear、Settings、Check），避免在膠囊內換行或跑版；中文不受此限。`EnglishButtonLabelTests` 檢查清單內的按鈕 key，新增按鈕文案須加入該清單。

Figma 內部不一致（記錄、不視為已設計）：`Toast / 系統訊息 / warn` 元件預設按鈕為「繼續」，D10 說明文字提到「重試」，但 D10 畫面渲染的 action 為「繼續」；以渲染為準，App action 顯示「繼續」並沿用恢復路線行為。此說明取代先前「Warning／Danger Toast 固定 80 pt、實心 1 pt 邊框」描述中的高度與邊框不透明度。`StatusPill / 連線中斷` 舊版名稱／文字不一致已由 2026-10-30 回讀修正，現行渲染標籤為「連線中斷」。

## 2026-10-24 Section E補充定案（線框修正與實作分開追蹤）

- E區UI佈局以04頁light theme渲染為主；dark theme沿用相同結構、動作與尺寸，只調整主題tokens。E5依淺色恢復列＋tabs同步深色，取代先前恢復態隱藏tabs的建議；E2正常執行態仍隱藏tabs。
- 自動漫步「更換地點」為E2底部按鈕：沿用目前模擬位置，按最新速度自選終點並重新規劃道路，成功後接續。
- 速度pill與設定移動速度sheet都與路線共用UI模組，涵蓋格式、快選、slider、提交與持久化速度偏好，不僅同步數值。
- 漫步確認目的地後的鏡頭（2026-10-26 使用者指示）：不再框住整段路線，改為只平移、保留縮放，把模擬箭頭放在地圖高度 1/3 處，避免被搖桿 panel 蓋住。
- 按鈕不因 heartbeat 閃爍（2026-10-26 使用者回報）：保持位置／keep-alive heartbeat 寫入期間服務短暫忙碌，會暫時撤銷 admission。路線「開始」、暫停中的「恢復」、「自動漫步」、瞬移 Pin 的 Go 與搖桿握柄只有在不可用狀態持續超過 1 秒才顯示停用；點擊仍由控制器檢查 admission。地點卡（LocationCard／PlaceDetails）主按鈕也套用，顏色隨同一延遲停用狀態變化。
- 漫步候選使用瞬移 CandidatePin（2026-10-26 取代 DestPin）；已生效目的地只以路線終點粗圓點呈現，不另疊 Pin；點擊該圓點（44 pt 命中區，VoiceOver 為按鈕）開啟目前目的地的地點卡；Pin 浮鈕與 location card 主要按鈕均為純文字「確認」，不帶播放 icon，兩者送出同一重規劃命令。手動搖桿／瞬移仍為 Go，沿用共用瞬移命令。Figma E4 淺深色卡片現已修正並讀回渲染；App 行為分票實作。
- E1 保留搜尋列、tabs、150 pt 搖桿、速度 pill 與「自動漫步」按鈕；不得用 Toggle 取代。E2 保留完整搖桿及「停止漫步／更換地點」；E2.a 為同一任務的收合面板。淺色為結構準據，深色沿用相同結構與操作，只套主題 tokens。
- 漫步候選 Pin 與地點卡主按鈕均以「確認」送出同一重規劃命令；候選在成功前不取代目前目的地。E2 更換地點從目前模擬位置重選終點並規劃道路，成功才替換既有路線；規劃中留在最後 ACK。手動搖桿接管保留目前目的地，放開後由最新 ACK 位置重規劃，避免返回舊折線或接直線。
- 路段終點 ACK 後若使用者確認候選 Pin，從該 ACK 座標直接規劃選定的新終點，沿用已暫停 lease；不等待一般路線重規劃的 `.paused` 狀態。
- 漫步地圖 Pin 的地點卡顯示時，底部搖桿 panel 自動收至最小高度並保持；拖動 grabber 拉高可直接展開，點「搖桿」tab 也會恢復展開高度。關閉卡片不自動改回較高 detent。淺深色共用此行為，僅套用主題 tokens。
- scene 進入 inactive 時取消未提交的漫步道路規劃；返回 active 並通過 fresh recovery probe 後，沿用原目的地或 ACK 終點恢復規劃。Core resume admission 必須檢查 scene active；連線／背景恢復沿用原任務，獨立於規劃失敗 Retry。
- E3 速度 pill 與速度設定 sheet 必須呼叫路線共用元件；sheet 背景顯示開啟前的實際 session 狀態，不固定顯示舊「服務待命」。
- E5 恢復狀態使用恢復列與 tabs，接續原任務；規劃失敗使用獨立頂部 error Toast「無法規劃路線」＋「重試」，重試重新選目的地與規劃，不復用背景恢復入口。
- 沒有目前有效模擬位置或目前位置時，自動漫步從地圖視野中心周邊做最多三組起訖道路搜尋；有效路段確認後才定位並以 ACK 起點，最後才啟動漫步。正常定位／暖機／歷史座標均不能單獨呈現為有效模擬中。失敗 Toast 使用共用 danger 樣式，重試入口重新規劃，不與 E5 的原任務續接共用。
- 自動漫步單次啟動（2026-10-26 使用者確認）：按一次「自動漫步」即自選目的地、取得道路路線並開始模擬，不需再按第二次；起點 ACK 時若保持位置仍在準備，等它結束後立即啟動，不判定為失敗。有效模擬位置不在道路上時，每段漫步路線先從目前模擬位置走到最近道路起點再沿道路前進，不因道路起點與目前位置不同而判定規劃失敗；抵達終點後自動以 ACK 座標選下一個約 10 分鐘距離的目的地（2026-10-26 使用者回報啟動即「無法規劃路線」；已修正，尚未實機驗證）。漫步路線同時只有一個目的地，地圖只畫起點與終點，不顯示中途停靠點（路線模式長路線的 1/3、2/3 標記不適用於漫步）。
- 地圖路線節點（2026-10-27 Figma 修正）：MapNode 起點、停靠點及目的地統一為 24 × 24 pt frame，外環均為 18 pt；起點為白色中心＋3 pt 黑色外環，停靠點為白色中心＋2.5 pt 黑環及 11 pt 編號（僅路線），目的地為白色中心＋4 pt 黑環且沒有黑色中心點，無短桿並置中對位路線終點，路線與漫步共用。Pin 唯一保留 CandidatePin（30 × 44 pt，白色 Pin 頭、黑色描邊與黑短桿）；DestPin 元件與目錄卡已刪除。不得把 MapNode／Pin 畫成整顆實心黑圓。以上是 Figma 形狀與顏色規格更新；App SVG／渲染尚未更新或裝置驗證。

- 2026-10-24 漫步續航規格：終點 ACK 後以 ACK 座標作下一段起點，按最新速度選終點並規劃；失敗時保留起點、自動重新選終點重試一次（每次換段最多兩次嘗試）。成功接續；仍失敗才顯示「無法規劃路線」＋「重試」。等待時停留、不使用直線 fallback；使用者點 Toast 重試按目前有效模擬位置→目前位置→必要時自選起點的優先序解析起點。選點距離預算為速度×600 秒，不保證實際道路時間為十分鐘。

## 2026-10-25 使用者回報修正（設計與實作狀態）

以下為使用者確認的設計更新，已實作並通過 core 測試與模擬器 build；尚未在實機逐項驗收。

- 有標題的 sheet／全螢幕清單頁（最愛地點、最愛路線、匯入路線、編輯最愛、新增／編輯最愛路線、時速設定）標題一律水平置中於頁面，不受左右按鈕寬度影響（共用 `GoFlySheetHeader`）。
- 最愛地點、最愛路線清單頁以 `NavigationStack` 原生 push 呈現；畫面自繪標題時隱藏系統導覽列，但保留左緣滑動返回。Figma 04 規範畫面結構，沒有指定轉場動畫；此原生 push／edge-swipe 行為屬 App 導覽實作。
- 最愛清單頁（地點與路線）：搜尋欄 focused 時，點清單、空白處或標題列即取消 focus 並收起鍵盤；捲動清單亦收起鍵盤。
- 路線執行控制列（D6）：來回鈕使用 Figma ⇄ 圖示（開為 primary、關為 secondary），方向鈕 ↓↑ 鎖定時兩箭頭用 disabled 文字色但仍可見；時速 chip 在執行中與暫停時可點，改速度從下一步起生效，不重開任務。
- 使用者按「暫停」的路線不顯示 warn toast（D10 面板已說明）；系統中斷（背景、連線等）仍顯示 D10 warn toast。
- App 離開／回到前景時，暫停類 warn toast 在場景回到 active 約 1 秒後才顯示，避免系統快照與回前景第一幀閃出黃色 toast。根因未由實機診斷證實（2026-10-25 診斷顯示瞬移維持在背景期間持續執行、無 pause 事件），需實機確認是否已消失。

## 2026-10-26 Figma 設計稿更新（背景運行時間）

- **F6 · 設定 › 背景執行**：第一群組「路線與漫步」＋「背景運行時間」（預設「1 hr」、chevron），第二群組「背景 App 重新整理」（y 234）。F6、Dark F6 與 F6.a／Dark F6.a 底圖都已移除說明文字（2026-10-26 Figma 同步）。
- **F6.a · 背景運行時間 sheet**：規格見上方「背景執行設定」條目（雙滾輪＋冒號、完成設定按鈕；無目前設定卡、無上限膠囊、無說明小字）。淺色 `F6.a`（`238:9408`）與深色 `Dark · F6.a`（`238:9488`）；深色版已移除快速選擇列、「上限 24:59」膠囊與分隔線，元件位置與淺色一致，取消／完成改為主要文字色。兩版已移除「目前設定」卡，sheet 改為 336 pt（2026-10-26，App 與 Figma 已同步）。
- **F6.a 滾輪單位與選取列版面（2026-10-26 使用者確認，App 已實作，尚未裝置驗證）**：每個數字 row 不帶單位；單位固定於選取列旁，不隨滾輪移動，非選取列不顯示單位。英文為 `hr`／`min`，中文為「小時」／「分鐘」。左右 Picker 等寬，選取灰底相對冒號左右對稱；數字使用 iOS `title2`，比一般欄位字級稍大，數字與單位之間保留清楚間距。Figma 淺／深色靜態稿已呈現僅選取列有單位，互動中的固定位置、灰底對稱、數字字級與數字單位間距由本規格補充，Figma 未修改。驗收：捲動小時或分鐘時，單位保持各自固定位置且只與當前選取數字列對齊；兩側選取灰底寬度相同，中心到冒號距離相同；選取數字與單位不貼合或重疊。
- Figma F6.a 讀回：完成設定按鈕下緣到 Home indicator 為 40 pt，與「按鈕到 indicator 統一 20 pt」規則不一致；2026-10-26 使用者確認以 App 為準，F6.a 維持 40 pt，為 20 pt 規則的例外。
- **路線 Mode 地圖控制（MapControls）增設 FitRoute 按鈕**：
  - 於 `0 · 共用元件` 新增 `FitRoute`（淺色）與 `Dark · FitRoute`（深色）44 pt 圓形圖示按鈕組件，內嵌標準 SF Symbol `arrow.up.left.and.arrow.down.right` 對角雙向展開箭頭圖示（`icon/expand`）。
  - 功能：點擊自動調整地圖鏡頭 pan 與 zoom，以最適比例完整容納（fit）當前規劃中或行進中的整段路線及起訖點。
  - 配置位置：於路線 mode 所有 24 個含地圖之 frame（D1–D10.a 淺深色全覆蓋）之 `MapControls` 內，配置於「回到定位（Recenter）」按鈕正上方（間距 8 pt）。Recenter 繼續保持距底部面板上緣 16 pt。

- 設定移動速度 sheet 版面對齊最愛地點 sheet（C2，2026-10-26 使用者指示）：Grabber 距頂 6 pt、無標題、無右上「完成」（2026-10-26 使用者指示，只靠「完成設定」按鈕關閉），內容區上緣縮小（速度列距頂 32 pt）、內容左右 20 pt、區塊間距 16 pt、「完成設定」按鈕左右 20 pt 並距底部安全區上方 12 pt；sheet 高度 412 → 329 pt；滑桿區 48 pt、與「完成設定」相距 40 pt；所有間距與元件高度採 4 pt 倍數（快選膠囊高 38 → 40 pt）。Figma D7、E3、Dark D7、Dark E3 與 App（`GoFlySpeedSheet`）已同步；尚未裝置驗證。
- 按鈕與 Home indicator 間距（2026-10-26 使用者指示）：Figma 04 頁所有緊鄰 Home indicator 上方的 Button（R02–R06、C2、D6／D6.a／D7／D10／D10.a、D11–D18、D20、E2、E3、F6.a 與深色版）統一為按鈕下緣到 indicator 上緣 20 pt（原多為 21 pt；E2 為 53、F6.a 為 22／27、E3 為 33）。App 目前只有設定移動速度 sheet 以 `padding(.bottom, -1)` 對齊；其他畫面（onboarding、最愛、GPX、背景運行時間等）尚未逐一檢查，未裝置驗證。
- 按鈕與 TabBar 間距（2026-10-26 使用者指示）：緊鄰 TabBar 上方的 Button（D1／D2／D8／D9／D15 的「開始」、E1／E3 的「自動漫步」、E5 的「恢復漫步」與深色版）統一為按鈕下緣到 TabBar 上緣 20 pt（原 35／16／36／18）；面板上緣與地圖 Recenter／FitRoute 隨之移動。App 已將路線與搖桿面板底部內距由 36 改為 20（路線面板容量與搖桿預設高 352 → 336 同步調整）；E5 恢復面板為固定高度膠囊，尚未調整；未裝置驗證。
- 面板高度實作值（2026-10-26 與 UI test 對齊）：所有面板頂部為 33 pt grabber 列（距頂 8 pt、膠囊 5 pt、到內容 20 pt，`GoFlyGrabber`），內容在其下依 4 pt 網格排列，底部按鈕距 TabBar 20 pt。瞬移半開面板依目前內容自適應，最多 305 pt、最小 120 pt（B2／B1）；Figma 04 的 B2 靜態稿展示兩筆最愛的滿高狀態，少於兩筆時的高度變體尚未設計。路線依內容約 345 pt，收合 96 pt（D1／D3，Pin 收合同為 96 pt）；搖桿預設 349 pt、收合 96 pt（E1／E1.a；取代上列「352 → 336」）。路線執行時速 chip 最小寬 68 pt、隨數值變寬。Figma 中的 76 pt 收合高度、12 pt header 間距與 36 pt 底距為舊值。
- C2「編輯最愛」與 D20「新增最愛路線」sheet 比照 D7（2026-10-26 使用者指示）：Grabber 距頂 6 pt、標題列 y22、標籤 y76、輸入欄與資訊卡間距 16 pt、資訊卡到主按鈕 40 pt、主按鈕高 56 pt、sheet 高度 367 pt（原 462）；sheet 內自帶 Home indicator，淺深色同步。C2 按鈕下方留白自 2026-10-30 起依使用者追加要求為 40 pt；目前 Figma C2 渲染仍為按鈕下緣至 Home indicator 上緣 20 pt，記為 App 規格覆寫。D20 原 Home indicator 間距規則仍適用，待票 14 的明確追加修正。App：`GoFlyFavoriteEditorSheet`、`GoFlySaveFavoriteRouteView` 改為按鈕在內容內（上方 40 pt）、detent 367；最愛路線標籤編輯（`GoFlyFavoriteRouteLabelEditor`）尚未同步；未裝置驗證。
- 最愛地點 C2 與最愛路線 D20／標籤編輯：空白 label 儲存時仍以 `d MMM yyyy HH:mm`（英文月份縮寫、24 小時制、裝置當地時間）作為名稱 fallback；但依目前 Figma C2 渲染，最愛地點 label 欄位的 placeholder 固定顯示「標籤」，不顯示日期。最愛路線新增 sheet 要等收藏資料載入完成後才呈現，避免 `Save` 因載入狀態而暫時停用；sheet 縮小／展開不改變可儲存狀態。

## 2026-10-26 裝置服務卡：Start/Stop 與失敗後 Reset（使用者確認，App 已實作，未裝置驗證）

- 設定 F1「裝置服務」卡只保留主按鈕「啟動／停止」；「恢復 GPS」與「重置 VPN 通道」兩顆按鈕自卡片移除，改由下列規則取代。此規則取代 F1 線框目前並列的兩顆修復按鈕。
- 停止：結束所有任務、清除模擬定位並關閉定位 session（沿用 2026-10-25 規則）。停止成功即已恢復真實 GPS，不需再按「恢復」。
- 啟動：自行處理 VPN 通道／session 修復。上次 session 結束異常（上次操作留有錯誤、清除定位未確認、或裝置可能仍持有模擬位置）時，先捨棄舊連線並重建，再準備 session；第一次準備失敗後的每次重試也一律先重建連線。正常情況不額外重建，不增加啟動延遲。
- 重置（Reset）：只在「停止失敗」（停止後清除定位未確認，GPS 狀態未知）或服務卡住（`repairRequired`）時顯示，平時隱藏。按下後立即在本機結束所有任務與送點資格，再盡量重建連線並清除模擬定位；清除失敗不顯示錯誤、不卡住，只保留「GPS 未確認」，Reset 仍可再按，或直接再按「啟動」。按鈕文字「重置／Reset」，左側附 `arrow.counterclockwise` 圖示，排法與「啟動」的 play 圖示相同（2026-10-26 使用者更新；App 已實作，Figma F1.a 淺深色已同步為 `icon/reset`）。Figma F1.a Light／Dark Reset 均引用共用 `icon/reset`，箭頭頭部旋轉 0°、與圓弧相接且左側保留可見間距；Dark component instance 使用 Dark `color/icon/primary` token。此為 Figma 幾何更新，App SVG 未在本次變更，尚未裝置驗證。
- App 重開後手機仍殘留模擬位置的情況，仍由 recovery banner 的「恢復」處理，不依賴服務卡按鈕。
- 「設定 › VPN 通道」頁的「重置 VPN 通道」按鈕與其手動重置流程（2026-10-26 使用者確認）已刪除，修復改走設定首頁的「重置」；任務運行中的自動 reset tunnel 維持原狀。
- 錯誤文案：`error.tunnelUnavailable` 的修復指引由「在 GoFly 重置 VPN 通道」改為「在 GoFly 重新按『啟動』」。
- Figma 同步（2026-10-26 完成）：04 頁 `F1 · 設定首頁`（淺色 `121:53504`、深色 `121:56326`）已移除「恢復 GPS」「重置 VPN 通道」，服務卡縮為只有主按鈕；新增 `F1.a · 設定首頁 / 停止失敗`（淺色 `239:15235`、深色 `239:15337`，位於 F3 右側），紅色「錯誤」pill、主按鈕「啟動」與下方「重置」，並更新 F1／新增 F1.a 說明。殘留差異：F1 主按鈕仍寫「停止服務」，App 為「停止」；紅色 pill 使用元件 `StatusPill / 連線中斷` 並覆寫文字為「錯誤」，元件名稱待同步為「錯誤」。
- 驗收：正常停止後卡片只有「啟動」且 GPS 恢復；製造停止失敗（例如停止時中斷 Wi‑Fi／LocalDevVPN）後出現「重置」，按下後狀態回到停止、無紅色錯誤，恢復連線後再按一次可確認 GPS；通道異常後直接按「啟動」可自行重建並成功模擬。實作位於 `ServiceController.start()`／`forceReset()` 與 `ServiceSettingsView`；尚未真機驗證。

## 2026-10-27 Figma 04 iOS theme 色彩更新（取代舊深色值）

- iOS 維護自己的 theme 變數，不引用或共用 Mac 05 的變數。深色語意色值與 05 對齊：畫布 `#1E1E1E`、卡片／導覽表面 `#2C2C2E`、控制表面 `#3A3A3C`、輸入底 `#1C1C1E`、分隔線 `#38383A`、邊框 `#48484A`、主／次／停用文字 `#E5E5EA`／`#98989D`／`#636366`、accent `#0A84FF`、danger／warning／success `#FF453A`／`#FF9F0A`／`#30D158`。狀態底色延用 05 的 info `#182B40`、warning `#3A2B16`、success `#1D3225`；danger 底色 `#4D272A` 與地圖色票由 iOS 自行定義，05 沒有對應底色角色。地圖語意 token 保持 iOS 專屬。
- Figma 04 使用 `GoFly iOS / Light Theme`、`GoFly iOS / Dark Theme` 兩組獨立變數集合；目前 Figma 每組集合限一個 mode，因此各自以 Light、Dark 集合承載。每組有 94 個色彩變數，涵蓋語意角色與畫面專用色票；2026-10-27 為 Primary 按鈕新增 `color/action/primary/filled-surface` 與 `color/action/primary/filled-text`。先前的變數綁定覆蓋率盤點沒有發現所有語意角色誤套到單一畫面的問題，因此舊 Dark 總數不再作為完成依據；本次以逐 frame 綁定檢查為主，並對發現的異常截圖讀回。
- 2026-10-27 Dark frame-by-frame audit（速度插圖重繪前）：當次 04 `Dark` 區段 63 張完整 `393 × 852` frame、共 5,727 個圖層，5,170 個 paint properties 與 1,044 段文字填色均綁定 `GoFly iOS / Dark Theme`。其後速度插圖重繪使圖層數改變，舊數量不再視為目前統計；本輪已逐一確認 8 個 Dark 速度圖示使用 Dark `color/speed/*`。iOS Dark 變數獨立於 05 Mac collection。
- 本次修正逐 frame 核對發現的顏色角色錯配：B10／D8 的錯誤 toast 與 D9／D22 的成功 snackbar 僅保留各自狀態元件色，畫面底層恢復中性深色；D8 路線列、拖曳及排序控制恢復一般元件色；R04／R05／R06 步驟號改為次要文字色；B3／B4 確認文字、狀態列及 Tab Bar 色彩恢復可讀的 Dark token；F1／F1.a 兩個未綁色文字層改綁次要文字 token。Dark 地圖專用色票為：canvas `#131315`、building `#313133`、park `#1E3322`、water `#1A2B3C`、road `#3A3A3E`、road-edge `#2C2C2E`、arterial-edge `#6E5C2C`、arterial `#5C4F2A`、label-area `#8E8E93`、label-water `#6FA3D6`。
- 此變更更新的是靜態 Figma 線框與設計規格；App 色彩系統尚未據此修改，也沒有宣稱程式實作或實機驗證完成。已對修正畫面截圖讀回核對；本次沒有做裝置驗證。
- 2026-10-30 依當前 frame catalog 與只讀渲染確認 B11 Light／Dark 成對存在（Dark node `322:40470`）；舊紀錄曾把 Dark 列為缺口，現已解除。兩種外觀的 `StatusPill / 連接中` 依各自 theme 渲染。
- 本次讀回取代前文 2026-10-23 的 Dark variant 歷史缺漏清單；該清單中的 D1.a、D17、D1b 已不再是目前缺漏。B11 Dark 曾被列為缺口，2026-10-30 的 frame catalog 與渲染讀回確認 node `322:40470` 存在。

### Theme 驗收條件

- 04 的 Light／Dark UI frame 與文字、實心填色及描邊使用各自 iOS theme 變數；04 不綁定 Mac 05 變數。
- 深色表面與狀態角色依 iOS Dark tokens；主文字／icon 為 `#E5E5EA`，Primary surface／前景為 `#0066CC`／`#E5E5EA`。地圖與 iOS 專屬狀態角色保留在 iOS 集合。
- Dark 區段每張完整 UI frame 的實心填色、描邊及文字填色皆綁定獨立的 iOS Dark collection；狀態色只套用到對應的 toast、snackbar 或危險動作，不得因畫面名稱污染底層元件。
- 調整任一 iOS 變數時，引用該 token 的 Light／Dark frame 隨之更新；以逐 frame 渲染讀回確認元件底色、文字、圖示及狀態色仍具可辨識度。
- B11 Dark variant 已由當前 Figma frame catalog 確認存在（node `322:40470`）；Light／Dark 各自依渲染驗收，不互相推定。

### 2026-10-27 Dark · 0 · 共用元件（UI）

- Figma 04 `Dark · 0 · 共用元件`（section `256:16952`）集中整理非按鈕家族的共用 UI：狀態 Banner／Snackbar／Pill、搜尋欄與控制項、Progress、搜尋結果／清單、150 pt 搖桿及 Tab Bar。與 `Dark · 0 · 共用元件（按鈕）` 並排且頂端與內容板起點對齊；按鈕矩陣與色彩角色集中在按鈕區。此處的狀態動作只保留在 Snackbar 等使用情境，不重複按鈕 variant。Icon 目錄維持獨立整理；本輪只將 Search、history、nav、pin、gear、x、more 既有圖形資產設為可重用元件，供 Dark 搜尋欄、搜尋結果列與 `Button / Icon` 引用，不擴整其他 icon 目錄內容。
- 共用 Dark 規則：避免大面積純白；元件背景與作為底面的表面不得為純白 `#FFFFFF`；文字與 icon 不得使用純白。主要文字與 icon 使用 `#E5E5EA`，次要與停用前景依語意 token；主動作使用藍色 `#0066CC` 表面與 `#E5E5EA` 前景。其他狀態和控制表面沿用各自 Dark semantic tokens。
- `LIST · SEARCH RESULTS` 的 `Dark · List rows`（`222:13255`）已依 04 Dark B3／B4 搜尋畫面更新為三種列：最近搜尋（52 pt，history）、座標結果（64 pt，navigation）、附近地點（64 pt，location pin），移除舊版右側省略號及收藏／勾選混用列。樣式沿用來源列的深色圓形 icon surface 與文字／圖示變數。最近搜尋與地點名稱套用 `Theme/body`，座標主標套用 `Theme/bodyEmphasis`，副標套用 `Theme/footnote`。
- Figma 04 只有一套 `Theme/<token>` 文字樣式，不依 Light／Dark 分色。14 個 core styles 對應 `GoFlyFont` token，另有 `Theme/button/medium`（16 pt）與 `Theme/button/small`（14 pt）維持按鈕矩陣字級；Dark 按鈕與輸入欄元件、Tab Bar 標籤及羅盤方向字母均已綁定這套樣式。B3／B4 Light 與 Dark 搜尋列文字也使用同一套樣式。文字顏色仍由各自 `GoFly iOS / Light Theme`、`GoFly iOS / Dark Theme` 變數控制，樣式本身不帶顏色。
- Dark 狀態元件文字角色：Toast 標題與 action 使用 `Theme/subheadlineEmphasis`，說明與關閉符號使用 `Theme/footnote`；Snackbar 訊息使用 `Theme/subheadline`、action 使用 `Theme/subheadlineEmphasis`；StatusPill 使用 `Theme/footnoteEmphasis`。Toast／Snackbar／Pill 圖示、文字分別綁定 Dark 語意色，不以文字樣式代替顏色。
- `INPUTS · CONTROLS` 已改名為 `Dark · SearchBar`。Dark SearchBar 輸入區直接使用 E `Text Field / Neutral / Icon + Text / Default` instance（301 × 48 pt、y=1）；SearchField focused／normal 分別直接使用 E 的 Focused／Default instance（361 × 48 pt）。三者的 surface、border、搜尋 icon、caret 及 15 pt `Theme/subheadline` 由 E variants 提供；搜尋專用 placeholder 保留在 instance 上方並使用 `color/text/input/default`。貼上 glyph 使用 Icon 目錄 `icon/paste` 與 Dark `color/icon/input/default`，SearchBar／SearchField normal 右側為 44 pt 無底命中區。Settings 與 focused Clear 使用 `Button / Icon` 共用元件；Settings Enabled／Disabled 形狀為 48 × 48 pt、22 pt gear 置中、14 pt 圓角方形，SearchBar 中置於 50 pt 外框並與 48 pt Default input 對齊。搜尋列按鈕矩陣含 Settings、Clear、More 的 Enabled／Disabled variants。Progress 軌道使用 Dark `color/surface/card`，value 依使用者更新改綁 `color/surface/control`。
- Dark `LIST · SEARCH RESULTS` 左側三種列圖示分別使用共用 `icon/history`、`icon/nav`、`icon/pin`；右側 More 控制使用 `Button / Icon` 的 More variant，內含共用 `icon/more`。圖示綁定 Dark icon tokens；文字使用相同 `Theme/<token>` 樣式家族與 Dark 文字色變數。
- Switch 已不屬於目前 E2 漫步控制稿，Dark 共用元件也未建立 Switch variant；保留 E2 目前已確認的停止／更換地點按鈕配置，不重新加入 Switch。
- Figma 已更新 Dark 主文字／主 icon、按鈕前景及色票變數，兩區說明文字已同步；搖桿底盤使用 Dark 控制表面。兩區可見實心填色與描邊讀回均無純白值，並以截圖確認分組、間距、文字與 icon 前景。此為 Figma 靜態設計與規格更新；App 色彩程式未在本次修改，也未做裝置驗證。
- 驗收：非按鈕 UI 類別集中在 UI 區，不和按鈕矩陣或獨立 Icon 目錄重複；兩區標題、板頂與內容起點對齊，元件分組清楚且無重疊；Dark 元件背景不使用 `#FFFFFF`，icon／文字不使用 `#FFFFFF`；搜尋結果列圖示與 B3／B4 一致，文字引用共用 Theme 樣式且保留 Light／Dark 色彩變數。

### 2026-10-27 Dark 共用按鈕元件整理

- Figma 04 新增 `Dark · 0 · 共用元件（按鈕）`（section `249:16291`），作為 Dark 按鈕與文字欄位的集中整理區。元件顏色使用獨立的 `GoFly iOS / Dark Theme` 變數；深色共用語意角色與 05 對齊，但不引用 Mac 變數。移除舊 A 區、新增 icon Ghost，並同步 B Filled／Ghost、C Neutral 與 E 欄位狀態色和展示背景後，此區共檢查 418 個實心填色／描邊，皆綁定 iOS Dark 變數，無裸色值或跨集合綁定。
- 舊 `A · ACTION BUTTONS / Type × State`（`Button / Action`）元件組已移除；檢查全檔 804 個 instance，沒有任何 instance 引用它的 6 個 variants。新按鈕矩陣承接目前使用的 Primary、Neutral、Danger 與 Ghost 按鈕；`Destructive · text` 色彩角色卡保留，但新的 `Button / Text` 尚未定義 Destructive variant。Dark `Button / Icon` component set 現含 Standard／Route／Ghost Standard／Ghost Route／Clear／More 六種各有 Enabled／Disabled 的 Type，加上 MapControls 只有 Enabled，合計 13 個 variants；Settings 是 set 外獨立 48 × 48 pt 元件。`Button / Check` 收納 Selected／Unselected；`Button / Status action` 收納 Error／Retry、Warning／Continue、Success／Undo。此為目前靜態稿已定義的型別與狀態，不代表未列出的所有組合都已設計。
- `Button / Icon` 的 Standard／Route 為 Filled 外觀，Enabled／Disabled 分別使用共用 `color/surface/control/active` `#4C4C4F` 與 `color/surface/control/disabled` `#242426`；所有 Filled／Ghost Disabled 圖示使用 `color/icon/control/disabled` `#636366`。一般非按鈕 icon 的 `color/icon/disabled` 也為 `#636366`。
- Dark `Button / Icon + Text`／`Button / Text` 標籤依 Large／Medium／Small／Extra Small 使用 `Theme/bodyEmphasis`、`Theme/button/medium`、`Theme/button/small`、`Theme/captionEmphasis`；`Button / Status action` 用 `Theme/subheadlineEmphasis`，`Text Field / Neutral` 用 `Theme/subheadline`。所有字色仍保留 Dark Theme 變數綁定。
- `Button / Icon + Text` 與 `Button / Text` component sets 的主矩陣為 Type Primary／Neutral／Danger／Ghost Primary／Ghost Secondary、State Active／Disabled、Size Large／Medium／Small／Extra Small，三軸完整組合各 40 個 variant。尺寸為 Large `280 × 56 pt`、Medium `224 × 48 pt`、Small `176 × 40 pt`、Extra Small `144 × 32 pt`。Light C 另有 Primary Inline Active／Disabled（各 77 × 40 pt），Light D 另有 Neutral Inline Active／Disabled（各 86 × 40 pt），因此兩個 Light set 各 42 個、Dark 對應 set 各 40 個 variants。Danger Active 使用 Dark 專屬 `color/action/danger/surface` `#E14C46` 與 `#E5E5EA` 文字／圖示；Disabled 使用停用底色、文字與圖示。Danger 文字／圖示、邊線與 Toast 狀態色維持各自的語意 token。兩種 Ghost 都無填色、無描邊；Active Ghost Primary 使用藍色 accent；Active Ghost Secondary 的文字／圖示使用 `color/text/primary`／`color/icon/primary`（`#E5E5EA`），與 B · ICON BUTTONS 的 Enabled 色一致。Disabled Ghost Primary／Secondary 的 icon／text 使用專用按鈕停用 token（`#636366`），與 B · ICON BUTTONS 的 Disabled 色一致。C 的 Primary／Danger、Neutral、Ghost 各 Disabled 文字／圖示均為 `#636366`，分別沿用共用、control、button 語意 token。
- 按鈕色彩角色：Filled Primary 綁定 iOS 專用的 `color/action/primary/filled-surface` 與 `color/action/primary/filled-text`；Light 使用藍底白字 `#007AFF`／`#FFFFFF`，Dark 使用藍底與非純白前景 `#0066CC`／`#E5E5EA`。Dark 共用 `color/action/primary/surface`／`color/action/primary/text` 亦同步為 `#0066CC`／`#E5E5EA`；引用這兩個語意 token 的 Dark 元件會一併更新。Danger 填色由 `color/action/danger/surface` 控制（目前 `#E14C46`）；Danger 文字／圖示／邊線與 Toast 色由各自語意 token 控制。Secondary 使用卡片表面、分隔線描邊與主文字；Disabled 使用停用底色及停用文字／圖示；Destructive 文字按鈕使用 danger 文字色。勾選 Selected 使用深色表面與藍色勾記，Unselected 使用深色表面與次要描邊；兩態均不使用純白底。狀態操作只使用所屬 Error、Warning、Success 語意色；Info 保留狀態色參考，不增加未設計的動作按鈕。
- `Text Field / Neutral` 包含 Text 與 Icon + Text 兩種內容，每種有 Default、Focused、Disabled 三態（共 6 個 variant）。Default 與 Focused 底色使用共用 `color/surface/control/active` `#4C4C4F`；Default placeholder／icon 使用 `#BEBEC2`，邊框 `#636366`。Focused 保留 accent 描邊、`#E5E5EA` 輸入值與 caret。Disabled 底色使用共用 `color/surface/control/disabled` `#242426`，文字／圖示使用 `color/text/control/disabled`／`color/icon/control/disabled`（`#636366`）、邊框為 `#38383A`。元件展示區背景使用 `color/canvas/button-board` `#101012`，內層面板使用 `color/surface/button-board` `#1C1C1E`。
- 此區只表達靜態 wireframe：Active／Disabled 按鈕、Default／Focused／Disabled 欄位、Selected／Unselected 勾選及狀態動作；沒有 hover／pressed 畫面或 prototype wiring。更新的是 Figma 設計，未表示 App 元件已實作或經裝置驗證。
- 驗收：Primary 與 Danger 維持各自 iOS Light／Dark tokens；B Filled 與 C Neutral 的 Active／Disabled surface 綁定共用 `color/surface/control/active` `#4C4C4F`／`color/surface/control/disabled` `#242426`；B Ghost 無填色／描邊，Enabled 圖示使用 `#E5E5EA`；B Disabled icon、C/E Disabled text／icon 均使用 Dark Theme token `#636366`。E Default／Focused 與 Disabled 欄位底色使用相同兩個 control tokens，前景、描邊與 caret 綁定 iOS Dark tokens；E Default placeholder／icon 為 `#BEBEC2`。調整 shared token 後引用元件同步更新；截圖確認狀態、背景層次與 Disabled 前景。



### 2026-10-27 04 iOS Icon 目錄

- 速度圖示色塊規格（2026-10-28 重繪，取代先前 walk 姿勢與 bicycle 線架規格）：`speed/walk`、`speed/bicycle`、`speed/scooter`、`speed/car` 四個 36 pt master 全部由封閉填色 shape（色塊）組成，可見圖層無 stroke、元件底色透明。walk 為前傾行走人物：navy 圓角膠囊四肢（後腿彎膝）、coral 實心上衣、skin 頭與手、navy 髮型、gold 圓角鞋；bicycle 以 coral 實心圓角管件組成車架、navy 座墊／把手／前叉、gold 齒盤；scooter 為 coral 實心車身與前擋泥板、navy 座墊與把手、gold 頭燈；car 為 coral 實心車身與車艙、sky 車窗、gold 頭燈、coral-shadow 尾燈。三款車輪統一為 navy 實心輪胎、highlight 輪框與 gold 輪轂。填色綁定 `color/speed/*`。D7／E3 淺深色 16 個「Speed icon」直接使用這四個 master 的 instance（22 × 22 pt，原位置），Dark 實例覆寫為 Dark `color/speed/*`；`00` 頁的 `WF/Icon/speed-*` 24 pt source 已不再被 D7／E3 引用。驗收：Icon 目錄 36 pt 與 D7／E3 Light／Dark 截圖中四款圖示造型一致、無描線、在 22 pt 仍可辨識；Figma 截圖已讀回，此靜態設計未更新或驗證 App `SpeedPreset*` 資產與實機顯示。

- `0 · 共用元件（Icon）` 位於 04 `iOS Redesign`（Figma section `256:17781`），收錄通用功能圖示與速度預設圖示；`0.a · 共用元件（Icon）`（section `340:21618`）集中收錄有主題或狀態差異的 `map/*` 圖示，包括 SimArrow Light／Dark 與等待態、RealArrow、CandidatePin 及 MapNode 起點／途經點／終點。兩區只收錄 04 頁出現的 SVG／向量圖示（含 `icon/check`）；05 Mac 專用圖示與 glyph 不納入。Figma 向量圖歸在 SVG 類；卡片數量與位置以 Figma 當前內容為準。
- 功能 icon 以空心描邊為主，24 pt 線寬 1.9 pt、圓端／圓角；播放／暫停／停止等 Figma 明確設計為實心的符號維持實心。`GoFlyIcon` 使用 `Assets.xcassets` 的共用向量資產，`GoFlySymbols` 僅提供語意別名；地圖／狀態變體依各自 Light／Dark 與等待狀態保留填色、描邊及透明度差異。`icon/speed` 儀表維持原樣；`speed/walk`、`speed/bicycle`、`speed/scooter`、`speed/car` 為 36 pt 彩色色塊插圖，四款均以實心填色 shape 構成、不使用描線（含單車車架與車輪）。D7／E3 淺深色實例直接引用這四個 master。地圖箭頭、候選 Pin 與路線節點以原始比例及狀態色置於 0.a `map/*` 區，保留各自用途；既有畫面圖示保留各自尺寸與位置；速度預設引用更新後的共用插圖及對應主題色。四款速度插圖另各有一張 selected 展示卡，背景使用 Figma Light `color/action/primary/surface`（綁定 theme variable）、文字為白色，基礎插圖本身不變。6 個基礎 `WF/Icon` 各有可搜尋的 24 pt 共用元件，內嵌局部外觀覆寫，原始 master 保留。整理期間 `slider.horizontal.3` 卡片在 Figma 目錄中被移除，其基礎 master `9:207` 仍存在。
- 命名統一採簡短英文：`icon/expand`（原 `icon/arrow.up.left.and.arrow.down.right`）、`icon/reset`（原 `icon/arrow.counterclockwise`）、`icon/direction-forward`／`icon/direction-reverse`，以及 `speed/walk` 等；地圖等待狀態使用 `map/sim-light-wait`／`map/sim-dark-wait`。原元件 ID 保留，舊名稱記在描述中供搜尋。
- 四個速度插圖共用 navy、coral、coral-shadow、gold、skin、highlight、sky 七種 `color/speed/*` 色彩，Light／Dark 各自綁定對應主題 collection；16 個 D7／E3 淺深色預設圖示為 `speed/*` master 的 instance，保留 22 pt 與原位置。此為 Figma 設計更新，App `SpeedPreset*` 資產及裝置狀態未在本次更新或驗證。
- 單色功能 icon 使用黑色 `#000000`，保留圖形內部留白／負空間；alert、success、速度插圖及定位 symbol 保留語意色。`icon/success` 勾色與 success 圓環同步（Light `#34C759`、Dark `#30D158`；黑底勾選框內為白勾）。Check／選取使用可重用 `icon/check` 向量，勾形與 `icon/success` 內勾一致；`icon/select` 的勾線同形，兩者皆為圓端／圓角。Close 僅保留 `icon/close`，Grip 僅保留圓端線條的 `icon/grip`；`icon/paste` 為透明底的圓角描邊 clipboard，由主體輪廓與置中、封閉的圓角矩形夾扣構成；24 pt 母元件線寬 1.9 pt、主體圓角 2 pt，比照 `icon/copy`。24／20 pt 母元件、內層框架及所有 18／20 pt 使用實例設為雙向 SCALE constraints；外層容器等比例放大時，圖示與位置同步縮放，不疊加重複圖層。已刪除未使用的 `icon/repeat.muted`、`icon/location` 與 `mappin.and.ellipse` 目錄卡；定位箭頭統一用無填色、1.9 pt 黑色描邊的空心 `icon/nav`；通用 Pin 使用 `icon/pin`。`icon/direction-forward` 左側箭頭透明度為 40%，`icon/direction-reverse` 右側箭頭透明度為 40%；`icon/swap-horizontal` 使用雙向 `arrow.left.arrow.right`。
- SimArrow 與 RealArrow 均使用 22×22 pt frame，箭頭輪廓與 24 pt `icon/nav` 等比例縮放至 22 pt 後一致；SimArrow Light 黑色填色／白色描邊，Dark `#E5E5EA` 填色／黑色描邊，不使用綠色或紅色；等待態沿用同色並以 50% opacity 呈現。RealArrow 保留 `#007AFF` 實心藍填色、`#E5E5EA` 描邊與微陰影。RealArrow Light／Dark master 與 B8 實例已更新為此輪廓與顏色，保持地圖位置中心，並已截圖讀回。`icon/reset` 的箭頭頭部為水平／垂直圓端線，旋轉 0° 並與圓弧相接，左側保留可見間距。F1.a Light／Dark「重置」按鈕均引用此 component，Dark 實例描邊綁定 Dark `color/icon/primary`。MapNode 三種節點均為 24 pt frame／18 pt 外環，目的地描邊 4 pt 且無中心黑點；Pin 僅保留白頭、黑描邊及黑短桿的 CandidatePin。此為 Figma 形狀規格；App 以 `GoFlyIcon`／`map/*` catalog 資產繪製，裝置顯示尚未驗證。
- `0 · 共用元件（Icon）` 的 SVG／向量卡以 component master 或 component instance 提供可重用圖示；`icon/pin` 卡保留在 04 目錄供 B4 Search Sheet options 引用；`icon/paste` 預覽保留巢狀 component instance，主體輪廓與封閉夾扣完整，並可隨容器等比例縮放。`icon/check` 置於 `SVG · VECTOR ICONS`，可直接搜尋；功能圖示使用語意色 token override 時仍須依 Light／Dark 主題綁定正確 token。
- 驗收：04 各有一個 `0 · 共用元件（Icon）` 與 `0.a · 共用元件（Icon）`，00 不保留 Icon 目錄；圖示來源限於 04，`0.a` 收納多狀態 `map/*` 卡片；速度圖示在 `0` 區各有基礎與 selected 展示卡，selected 背景綁定 Light `color/action/primary/surface` 並保持白色可讀文字。每個圖示皆能透過 component master 或 instance 重用，`icon/check` 可搜尋且勾形比照 `icon/success`；單色功能 icon 黑色，指定語意 symbol 保留色彩；非速度預覽均為 24 × 24 pt 置中區，功能 icon 使用 1.9 pt 圓角描邊，速度儀表保留原樣，四款速度插圖為無描線的實心色塊插圖，D7／E3 淺深色實例為其 instance 且造型一致；paste 主體與封閉夾扣清楚相接、內部留白可辨，線條與圓角比照 copy；母元件、內層框架及所有使用實例皆為雙向 SCALE constraints；容器 44→88 pt 時，20 pt 圖示 20→40 pt 並保持置中；`icon/location` 與 `mappin.and.ellipse` 已刪除，分別以空心描線的共用 `icon/nav` 與 `icon/pin` 作定位箭頭及 Pin；Close、Grip、repeat、direction 及更換 icon 符合規格。MapNode 三種 frame 均 24 pt、目的地 4 pt 外環且無黑點；只保留 CandidatePin。SimArrow 的 22 pt frame／向量外形與 24 pt `icon/nav` 等比例一致，Light／Dark 僅用黑白配色、等待態 50%；RealArrow 為 22 pt frame，箭頭向量尺寸／外形同 SimArrow 並與 `icon/nav` 等比例一致，保留藍色填色、淺灰描邊與微陰影；`icon/reset` 箭頭與圓弧保留間距；F1.a 淺／深色 Reset 均引用共用 component 並使用相符 icon token；`icon/pin` 可搜尋且 B4 Search Sheet options 仍能使用；卡片版面無重疊。App 的共用向量圖示透過 `GoFlyIcon`／`GoFlySymbols` catalog 使用，asset 與 catalog 對應由 `GoFlyIconCatalogTests` 驗證；本次不新增 prototype wiring，裝置外觀仍待驗收。

- Figma 現況差異：Light `SearchField / normal` 與 B3 的 20 pt paste instance 使用白色描邊，在白底不可見；Dark B3 的 20 pt paste 使用 `#2C2C2E`，在輸入欄上對比偏低。此為既有 instance 的色彩覆寫；速度 chip 25 km/h Selected 已依 2026-10-30 CS token mapping 更新規格：Default 為 `color/surface/card`／`color/line/border`，Light Selected 為 `color/surface/card`／`color/icon/accent`，Dark Selected 為 `color/surface/control`／`color/icon/accent`，選取數字使用 accent 文字。App 截圖驗證狀態記於票 12。

### 2026-10-27 04 iOS Typography 共用樣式目錄

- 04 新增 `0 · 共用元件（Typography）`（section `260:20013`），與 `0 · 共用元件（Icon）` 並排。目錄展示 14 個 core `Theme/<token>` 與 2 個 `Theme/button/*` 樣式，共 16 個 Figma 本機 text styles；每列範例直接套用對應 style。原 `0 · 共用元件（正式版 token）` 中的 6 個字體示例也改綁 `Theme/display`、`Theme/title`、`Theme/headline`、`Theme/body`、`Theme/footnote`、`Theme/caption`，取代舊 Large Title／Caption 說明。字體為 PingFang TC，字級與字重依 [`IOS-TYPOGRAPHY.md`](IOS-TYPOGRAPHY.md)，Light／Dark 共用同一套樣式。
- Figma Theme text style 只定義字型、字級與字重，不含文字顏色；元件文字仍須另綁各自 Light／Dark theme 文字色變數。`Theme/button/medium`、`Theme/button/small` 是 Figma 設計補充，不代表 App `GoFlyFont` 新增 token。
- 驗收：04 只有一個 `0 · 共用元件（Typography）`；16 列範例皆讀回正確的 style ID、字級、字重與 PingFang TC 字體，14 個 core styles 和 2 個 button styles 分組清楚；文字色規則與 Light／Dark 綁定說明可辨識，板面無重疊。此為靜態 Figma 更新；App 字體程式與裝置狀態未變更或驗證，也未新增 prototype wiring。

### 2026-10-27 Dark／Light wireframe 對齊

- 04 Dark 成對畫面依 Light 的結構與元件位置同步，保留獨立的 `GoFly iOS / Dark Theme` 色票，不改用 Mac 05 變數。完成範圍：R02／R06、B1／B10、D6／D8／D10／D10.a／D15、E4；D10 系列保留 Dark 中性色面板與藍色「繼續」主動作。當時記錄 B11 Dark variant 缺少；2026-10-30 只讀回確認 Dark node `322:40470` 已存在，故不再視為設計缺口。
- 2026-10-29 Figma 更新（僅 Figma 設計，App 尚未同步、未裝置驗證）：Dark D15 點位清單卡下緣到「取消／開始」按鈕上緣改為 40 pt（原 56 pt）；Dark `Button / Icon / 已匯入路線` 底色對齊 `Button / Icon / 最愛路線清單`（Dark 控制底 `#1A1A1C`，原 `#2C2C2F`），涵蓋 Dark D1、D15 與窄版 sheet 所有實例；Dark Button Theme board「B · ICON BUTTONS」所有 Enabled 填色 variant（Standard 各尺寸、Route、MapControls、Copy）母元件底色同步改為同一 token，與最愛路線清單按鈕一致。Light 已匯入路線按鈕底色同樣對齊 `color/surface/card`；Light D15 清單卡下緣到「取消／開始」按鈕上緣同樣改為 40 pt。
- Dark SearchBar 輸入區直接使用 E `Text Field / Neutral / Icon + Text / Default`，301 × 48 pt、y=1；底色使用 `color/surface/control/active` `#4C4C4F`，與 Light 301 × 50 pt 輸入卡保持各自設計。D8／D15 路線 sheet、D6／D10／D10.a 操作面板及 B1 收合 sheet 均依 Light 結構更新，並以 Dark token 重綁文字、底色與狀態色。B10 Toast 高度為 85 pt，內容換行與 Light 一致。
- 驗收：成對 frame 的主結構、元件尺寸與位置一致；Dark 填色、描邊、文字及 icon 維持 iOS Dark variables 並可讀；SearchBar 使用 E Neutral Default 的 Dark control surface；Light／Dark 成對畫面均經 Figma Console 截圖讀回。此為靜態 Figma 設計更新，未表示 App 已實作或完成裝置驗證。

### 2026-10-27 04 Light 共用元件與舊 Token 區移除

- 在 `04 · iOS Redesign` 新增 `Light · 0 · 共用元件`（section `268:21633`）及 `Light · 0 · 共用元件（按鈕）`（section `268:21877`），分別對應既有 Dark UI／按鈕元件板。保留原元件家族、variant、尺寸與排列，套用 `GoFly iOS / Light Theme`；Light 與 Dark 語意角色各自綁定 iOS theme collection，不引用 Mac 05 變數。
- Light UI 元件包括 Banner／Snackbar／StatusPill、SearchBar／SearchField、Progress、搜尋結果列、Joystick、TabBar、Recenter、FitRoute、SimArrow／RealArrow、CandidatePin 與 MapNode。Button 元件包括 Icon、Check、Status action、Icon + Text、Text 及 Text Field／Neutral。Light Primary Active 的 Icon + Text 與 Text 四種尺寸全部使用藍底 `#007AFF`／白色前景；Neutral Active 為 `#D1D1D6` 底與 `#C6C6C8` 邊，Disabled 為 `#F9F9F9` 底與 `#9999A0` 前景；五態 StatusPill 均使用白底；Danger 使用 Light 語意色。輸入欄 Default／Focused 使用白底、Disabled 使用 `#EEEEF0`，文字、圖示、描邊及 focus accent 使用 Light tokens。
- 原 `0 · 共用元件（正式版 token）`（`121:50484`）已從 04 刪除。其 28 個仍被使用的母元件移至 Light 主板下方的「iOS Light · 畫面引用中的原始元件」收納框（`268:22388`），以保留 249 個既有 instance 的 master ID 與畫面外觀；逐筆讀回均無失聯或改指。沒有被引用的舊 Switch on/off、Slider 與 List rows 隨舊區一併移除。這些被保留的既有母元件供舊畫面維持連結；新 Light 元件板提供新增設計所用的 Light variants。
- Figma Console 截圖已讀回 Light UI、Light 按鈕與既有畫面引用元件框；搜尋輸入遮罩已重綁 Light 白色輸入表面。此為 04 靜態 wireframe／元件庫更新，沒有修改 App 色彩程式、增加 prototype wiring 或完成裝置驗證。
- 驗收：04 僅保留 Light／Dark UI 與按鈕板、Icon 目錄、Typography 目錄；舊正式版 token 區不存在；Light 色彩 paint 綁定 iOS Light variables；Dark 元件維持 iOS Dark variables；既有 249 個 instance 的 master ID 全數保持，元件板與引用收納框無重疊。

### 2026-10-27–28 Light／Dark 按鈕、Snackbar 與搜尋列樣式調整

- Light `Button / Icon + Text` 與 `Button / Text` 的 `Type=Primary, State=Active` 四種尺寸全部綁定共用 `color/action/primary/filled-surface`（`#007AFF`），文字與 icon 維持白色。Neutral Active 綁定 `color/action/secondary/surface`（`#D1D1D6`），Disabled 綁定 `color/action/disabled/surface`（`#F9F9F9`），讓兩態明暗差異更清楚；邊線與 disabled 前景維持 `#C6C6C8`／`#9999A0`。
- 五個 Light StatusPill 狀態改用白底。Light `D · STATUS ACTIONS / Error × Warning × Success` 三個 action 按鈕使用白底，錯誤／警告／成功的外框和文字語意色保留。`Light · Snackbar / 可復原` 對齊 `Light · Snackbar / 2 秒自動消失`：白底、`#C7C7CC` 1 pt 灰邊與相同兩層 drop shadow。
- Dark `Snackbar / 可復原` 對齊 `Dark · Snackbar / 2 秒自動消失`：`#2C2C2E` 底、`#48484A` 1 pt 灰邊與相同兩層 drop shadow（9% y5 blur24、6% y1 blur3）。
- Light 與 Dark `SearchBar / 浮動` 的 `Button / Icon · Settings` 內層按鈕各自匹配 `Input / 搜尋框`：Light 為白底、`#C7C7CC` 邊；Dark 為 `#4C4C4F` 底、`#636366` 邊；兩者均為 48 × 48 pt，22 pt gear 置中、14 pt 圓角，並垂直對齊 48 pt 高的 Default input。
- 驗收：兩組 Light Primary Active 元件的四種尺寸均為 `#007AFF`；Neutral Active／Disabled variants 與圖例分別為 `#D1D1D6`／`#F9F9F9`；五個 Light StatusPill 為白底；Light Status Action 三鈕白底；Light 與 Dark 各自的可復原 Snackbar 底色、灰邊及兩層陰影分別與自動消失款一致；Light／Dark SearchBar 設定鈕為 48 × 48 pt、gear 置中並與 48 pt Default input 垂直對齊，顏色與線寬符合各自主題。Figma 元件板及 Light／Dark UI 截圖已核對；此為靜態設計更新，沒有修改 App、prototype wiring 或裝置驗證。

### 2026-10-28 搖桿刻度與方位字色調整

- Figma 04 的 Light／Dark `Joystick / 重新設計` 共用元件與 E1 畫面引用元件已同步：24 個刻度綁定 `color/icon/secondary`，刻度圖層 opacity 50%（Light `#8A8A8E`、Dark `#98989D`）；N/E/S/W 綁定 `color/text/secondary`。外圈、握柄、尺寸與排版維持原樣。
- App `GoFlyManualJoystickPad` 的刻度使用 `GoFlyTextColor.secondary.opacity(0.5)`，方位字使用相同次要文字語意 token；兩者都隨 Light／Dark 主題變化。
- 驗收：Light／Dark 共用元件及 E1 待命畫面顯示次要灰刻度與方位字，刻度不再綁 primary icon 色，字不再綁 primary text 色；Figma 截圖已讀回核對。此為靜態設計與色彩實作更新，未做實機裝置驗證，也未新增 prototype wiring。

### 2026-10-28 04 Light／Dark 色彩分類與 Surface Overlay

- 在 `04 · iOS Redesign` 將色彩整理為三個主要區塊：`Common Color`、`Light · Color Scheme`、`Dark · Color Scheme`。Common Color 展示共用 primitive（white、black、transparent、gray 50–950）；Light／Dark 分別展示主題色角色。各組色票分開排列並標明角色；Surface 色階由淺至深，同色角色合併標示於連續色帶，不為每個 surface 另開卡片。
- Primary 色階各列 `100／300／500／700／900`。Light 為 `#E6F2FF`、`#80BDFF`、`#007AFF`、`#005CBF`、`#003366`；Dark 為 `#E6F0FA`、`#80B3E6`、`#0066CC`、`#004D99`、`#002952`。500 沿用目前主動作藍色；其餘色階是新增的 palette 參考變數，不綁定既有元件。已使用的語意色變數及元件引用保留原值。
- 新增 Light／Dark `color/surface/overlay/*` 參考變數，透明度約 95%，供未來滿版地圖上的背景、卡片、Sheet、TabPanel 與 Panel 使用。Light 色值依序為 Background／Card／Sheet `#FFFFFF`、TabPanel `#F9F9F9`、Panel `#F2F2F7`；Dark 為 Background `#1E1E1E`、Card／Sheet／TabPanel `#2C2C2E`、Panel `#3A3A3C`。這些 overlay tokens 與現有不透明 surface tokens 分開，現有元件仍引用原 token。
- Light／Dark `Button / Icon + Text` 與 `Button / Text` 的 `Type=Neutral, State=Disabled` 四種尺寸均移除邊框，共 16 個 variants；其他按鈕填色、文字色與狀態色保留現有 Figma 值。
- 驗收：Common Color、Light、Dark 三個色票區齊全；色彩類別完整且 Primary 色階順序正確；Surface 色帶由淺至深、相同色值合併標示；新 overlay 色票為約 95% 不透明且未替換既有 opaque token；Neutral Disabled 的 16 個 variants 無描邊；既有元件使用中的色值未因新增色階而改動。這是 Figma 靜態設計更新，App 尚未據此實作，也未做裝置驗證。

### 2026-10-28 Color Scheme 回填附件 JSON 結構

- 將目前 Figma 色彩值整理到 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json) 的既有結構：`colors.primitive`、`themes.light`、`themes.dark`，各主題保留 `primary`、`secondary`、狀態色、`background`、`surface`、`text`、`border`、`action`、`overlay` 欄位。Light／Dark 主題色取自 04 共用元件及按鈕 variants 的現行 Figma tokens；primitive gray stops 取自現有中性色。未對元件重新綁色。
- 既有 `primary.scale`（100／300／500／700／900）與 `surface.mapOverlay`（背景、卡片、Sheet、TabPanel、Panel，95% opacity）收在原 JSON 的對應主題物件內。附件的 `overlay.backdrop`／`scrim` 欄位保留其原值；這兩者目前沒有對應的 04 元件 token。沒有 hover variant 的欄位沿用該角色現行顏色；所有欄位都有顏色值，沒有 `null`。
- Figma 三個區塊依參考圖排版：每組是一條橫向連續色帶，色名與 HEX 各列在對應色塊正下方，組與組之間留白。Common Color 放 primitive 共用色；Light／Dark 分組展示 Primary 色階、按鈕角色、各狀態角色、背景、文字、Surface、邊框、Action 與 Overlay。Surface 及 95% map overlay 依明度排序，同色角色合併標示；JSON 僅保留在 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json)。
- 驗收：JSON 可解析且附件定義的欄位均已補值；Figma 有 Common Color、Light、Dark 三個色票區，每個欄位均有對應色票、角色標籤與 HEX，沒有 JSON 文字框；截圖確認分組、Surface 明暗順序與 95% overlay。共用元件與按鈕的現有顏色、token 綁定及 variants 均保留；此為 Figma 靜態設計更新，未做 App 或裝置驗證。

### 2026-10-28 Color Scheme 以共用元件色值為準

- 色值方向為 `04 · iOS Redesign` 的 Light／Dark `0 · 共用元件` 與 `0 · 共用元件（按鈕）` → 對應主題 Color Scheme 色票及 `IOS-COLOR-SCHEME.json`。Color Scheme 是現有元件色值的整理展示，不作為元件或變數的色彩來源；本次只回填色票與 JSON，沒有反向改動元件。
- 依目前元件 token 校正對應欄位：Primary button text 為 Light `#FFFFFF`／Dark `#E5E5EA`；Success text／border 為 Light `#248A3D`／`#34C759`、Dark `#30D158`／`#30D158`；Light Warning／Error text 為 `#CC6600`／`#D70015`；Info surface 為 Light `#E5F2FF`／Dark `#182B40`。Light／Dark 色票標籤與 HEX 同步更新。
- 驗收：Primary text、狀態文字／邊線與 Info surface 的 Color Scheme HEX 對應現行 theme token；Surface Map Overlay 仍保留 95% fill opacity；共用元件、按鈕 variants 與 theme variable 值未變。Light／Dark Color Scheme 截圖與 Figma 節點讀回確認；此為 Figma 色票／規格整理，不代表 App 已實作或已完成裝置驗證。

### 2026-10-28 Light A–F 相近色沿用 Color Theme

- Light A–F 畫面中用途相同、僅色值相近的顏色直接綁定現有 Light Color Theme 語意 token；不為近似色新增 theme token，也不以 Color Scheme 色票反向設定元件。此規則適用於填色、描邊及文字色，角色相符優先於 RGB 數值相近。
- 本輪 62 個 Light App frame 的 5,194 個可見實心填色／描邊皆綁定 `GoFly iOS / Light Theme`，其中 205 個 paint 重新映射到既有語意 token。仍無法確認語意角色的 `#1C1C1E`（5 個執行提示底色）及 `#6B6B73`（1 個 dialog 說明文字）留在 Figma「未定義」色彩待確認區，沿用現有 palette 值，不新建 brand token。
- 驗收：A–F 相近且用途一致的顏色均引用既有 theme token；未知角色顏色只出現在「未定義」討論區；R04 保留使用者更新的排版與垂直配置。這是 Figma 靜態設計整理，App 尚未據此改色，也未做裝置驗證。

### 2026-10-28 Info Slate 與 Light Home Indicator

- Light／Dark Color Scheme 的 Info Main／Hover／Active、Text 使用 Slate 灰藍 `#475569`，作為低干擾的中性資訊／系統通知色；各主題既有 Info Background、Border 與 Contrast text 保留。Color Scheme 色票及 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json) 同步更新；目前沒有 Info 狀態按鈕 variant，因此不新增元件。
- Light A–F 的 65 個 Home indicator（含 sheet 內指示條）統一使用既有 Light Theme palette token `color/palette/3c3c43-3c3c43` `#3C3C43`。Dark Home indicator 維持原樣。
- 驗收：Light／Dark Info 主色與文字色的色票 HEX 均為 `#475569`；65 個 Light Home indicator 均綁定 `#3C3C43`，R04 版面和指示條位置不變；Figma 色票與代表畫面截圖已讀回確認。這是靜態 Figma 更新，未同步 App 或完成裝置驗證。

## 2026-10-28 Light Standard Icon Button（Figma 更新；App 待實作）

- 04 `Light · 0 · 共用元件（按鈕）` 的 B 區更新為 `Type × State × Size`。Light `Button / Icon` 的 `Type=Standard` 保留 Large 44 × 44 pt，新增 Medium 40 × 40 pt、Small 36 × 36 pt、Extra Small 32 × 32 pt；四種尺寸均有 Enabled／Disabled variants。Light component set 目前共 20 個 variants；Route、Ghost Standard、Ghost Route、Clear、More 各有 Large Enabled／Disabled，Copy 與 MapControls 各有 Large Enabled，Settings 仍為獨立 48 × 48 pt 元件。
- Standard Enabled 的底色綁定 `color/surface/card`（`#FFFFFF`），0.5 pt 邊線綁定 `color/line/separator`（`#C6C6C8`），圖示使用 `color/icon/primary`。Disabled 維持 `color/surface/disabled`（`#EEEEEF`）與 `color/icon/disabled`（`#9999A0`），不畫邊線。各尺寸使用 22／20／18／16 pt glyph；圖示引用 04 `0 · 共用元件（Icon）` 的 `icon/star` component，可替換為該共用目錄的其他 icon component。
- 7 個現有 Light Standard／Enabled instances 保持連結並繼承 Large 更新；已讀回 B 按鈕板、Light 共用按鈕區及 D15 代表畫面。此為 Figma 靜態 wireframe／元件更新，沒有加入 prototype wiring。App SwiftUI 尚未同步，較小視覺尺寸實作時仍須提供至少 44 × 44 pt 的觸控命中範圍；尚未做裝置驗證。
- 驗收：B 區清楚呈現 Standard 四種尺寸與兩種狀態；外框及 glyph 尺寸符合表列值；Enabled 為白底和 Light separator 邊線，Disabled 為停用灰底且無邊；Standard glyph 來自 Icon 共用目錄；其他類型、Dark 畫面與獨立 56 × 56 Favorite 控制不受影響；App 與裝置狀態仍標示為待處理。

## 2026-10-28 Location Card Actions / Map Pin 展示移除（後續已重新建立為共用元件）

- 04 `Light · 0 · 共用元件（按鈕）` 移除 `F · LOCATION CARD ACTIONS / MAP PIN` 展示列、標題、標籤及其 9 個展示元件主件。一般 icon-only 規格由 B `ICON BUTTONS / Type × State × Size` 覆蓋；icon + text 按鈕由 C `BUTTON / ICON + TEXT · Type × State × Size` 覆蓋，不再維護一組 Location／Map Pin 專用共用按鈕展示。
- B、C 按鈕板保留；B5、D4 等既有 location card／map pin 畫面中的操作仍保留原有視覺實例。移除的是按鈕板重複展示，不代表畫面操作已換成 B／C variant，也不推定各既有實例的尺寸可一對一對應到 B／C 尺寸。
- 驗收：Light 按鈕板不再有 F 標題、展示按鈕或標籤；B、C 規格列與其他按鈕板內容不變；既有 location card／map pin 畫面示例仍可見且外觀未變。這是靜態 Figma 整理，App 未修改、未新增 prototype，未做裝置驗證。

## 2026-10-28 C／D Button 內容置中（Figma 更新；App 待實作）

- 04 Light／Dark `Button / Icon + Text`（C）與 `Button / Text`（D）主矩陣的 40 個 variants 均使用水平 Auto Layout，主軸與交叉軸設為 Center，兩軸尺寸固定以保留按鈕尺寸。Light C 另含 Primary Inline Active／Disabled 兩個 variants（各 77 × 40 pt），Light D 另含 Neutral Inline Active／Disabled 兩個 variants（各 86 × 40 pt）；2026-10-28 為 Dark LocationCard 新增 Dark C Primary Inline Active／Disabled（各 77 × 40 pt），Dark D 無 Inline variants。C 的 icon 排在文字前、圖文間距 8 pt，整組置中；D 只有文字，置中且間距為 0。四組主矩陣共 160 個 variants，加上 Light C／D 與 Dark C 的六個 Inline variants，共 166 個 variants；文字層水平對齊 Center。
- 改變按鈕寬度時，Auto Layout 會將 C 圖文組或 D 文字重新置中。Light／Dark、C／D 的 Large 與 Extra Small、Filled 與 Ghost 代表 variants，以及 Light C／D 與 Dark C 的六個 Inline variants，均以放寬及縮窄方式讀回，置中偏移為 0，並恢復原尺寸；填色、描邊、文字與 icon 樣式不變。
- 驗收：C／D、Light／Dark 共 166 個 variants 均使用 Center 對齊與固定尺寸 Auto Layout；Light C/D 與 Dark C 額外 Inline variants 也能隨寬度改變保持置中；C 的 icon + text 為 8 pt 間距的同一組，D 文字單獨置中。四組 Figma component set 截圖與節點讀回確認。這是靜態 wireframe 更新，App 未修改、未新增 prototype，未做裝置驗證。

## 2026-10-28 Light LocationCard 與 Top / 執行指示共用元件（Figma 更新；App 待同步）

- 04 `Light · 0 · 共用元件` 的 `Light · LocationCard` component set（Figma `309:26980`）只保留 `Layout=Route`（361 × 180 pt、圓角 16 pt）；`Layout=Floating` 已刪除，B5／B7／D4／E4 四個 Light instances 全部改用 Route，並保留右上角共用 Clear X icon。卡片無描邊，fill 綁 `color/surface/overlay/card`（`#F9F9F9F2`，95% alpha），使用 12 pt Background Blur 與既有浮層陰影。
- LocationCard 操作列直接組裝共用按鈕：左側 Go 引用 C `Type=Primary, State=Active, Size=Inline`（77 × 40 pt）；右側 Star 引用 B `Type=Standard, State=Enabled, Size=Large`，Copy 引用 B `Type=Copy, State=Enabled, Size=Large`（各 44 × 44 pt、無文字）；右上 Close 引用 B `Type=Clear, State=Enabled, Size=Large`。沒有 Location／Map Pin 專用 F 按鈕組。
- 新增 `Light · Top / 執行指示` component set（Figma `309:26996`），含 `State=Active` 與 `State=Paused`。Light Top 使用 `#F9F9F9F2`、Dark Top 使用 `#2C2C2EF2` 95% overlay card surface，兩者皆有 12 pt Background Blur、主／次文字 token 與對應 nav／pause icon；不描邊並保留浮層陰影。Light／Dark D6、D7 使用 Active，D10、D10.a 使用 Paused；兩種主題的 D7 Top 均位於 Dim overlay 下層。
- Light／Dark B5／B7／D4／E4 LocationCard 與 D6／D7／D10／D10.a Top 均已替換為對應共用 component instances；Dark B7 的 Go 使用 Disabled，Pin 上方的 Confirm／PinConfirm 保留原狀。B7 error toast、B10 中性 panel 與 CandidatePin 顏色不在本次修改範圍。
- 驗收：LocationCard 僅有 Layout=Route；Light B5／B7／D4／E4 均連結同一 variant，無 Floating master 或 detached instances；卡片無邊框並使用 F9F9F2 95% surface／12 pt blur。Light 共用元件板、四個 LocationCard 畫面及 D6／D10／D10.a 截圖與 Figma 節點讀回確認；D7 Top 實際受 Dim overlay 遮擋。這是 Figma 靜態 wireframe／元件更新，沒有新增 prototype wiring，App SwiftUI 未同步，未做裝置驗證。

## 2026-10-28 Dark LocationCard 與 Top / 執行指示共用元件（Figma 更新；App 待同步）

- 04 `Dark · 0 · 共用元件` 新增 `Dark · LocationCard` component set（Figma `309:27199`），只保留 `Layout=Route`（361 × 180 pt、圓角 16 pt）。Dark B5／B7／D4／E4 全改用該 instance；B7 的 Go 為停用狀態。卡片無描邊，fill 綁既有 `color/surface/overlay/card`（`#2C2C2EF2`，95% alpha），使用 12 pt Background Blur 與陰影。
- 操作列由 Dark 共用按鈕組裝：Go 使用 Dark C `Type=Primary, State=Active/Disabled, Size=Inline`（77 × 40 pt）；Star 使用 Dark B Standard Enabled，Copy 使用新增的 Dark B `Type=Copy, State=Enabled`，兩者均 44 × 44 pt 無文字；右上 Close 使用 Dark B Clear Enabled。Dark `Button / Icon + Text` 新增 Primary Inline Active／Disabled 兩個 77 × 40 pt variants，文字為 Go；Dark `Button / Icon` 新增 Copy Enabled 44 × 44 pt variant。
- 新增 `Dark · Top / 執行指示` component set（Figma `309:27208`），含 Active／Paused 兩個 variants，使用 Dark `#2C2C2EF2` 95% overlay surface、Dark primary／secondary text 與 icon token；無描邊，保留陰影並加 12 pt Background Blur。Dark D6／D7 使用 Active，D10／D10.a 使用 Paused；Dark `Top / 漫步指示` 維持獨立畫面元件。
- 驗收：Dark 共用元件板新增 `MAP · LOCATION CARD / Dark` 與 `TOP · EXECUTION GUIDANCE / Dark` 區段；B5／B7／D4／E4 的 LocationCard 及 D6／D7／D10／D10.a 的 Top 都引用 Dark component instances。Dark B 按鈕板顯示 Copy Enabled，C 按鈕板顯示 Go Inline Active／Disabled。Figma 板與代表畫面截圖、variant properties、theme token 綁定及無邊框狀態已讀回核對。這是 Figma 靜態設計更新，未修改 App SwiftUI、未新增 prototype wiring，未完成裝置驗證。

## 2026-10-30 App implementation（票 05，取代以上 LocationCard 尚待同步狀態）

- App LocationCard 已同步目前 Figma Route variant：361 × 180 pt、圓角 16 pt、16 pt 左右內距、標題 17 pt／地址 13 pt／座標 12 pt，95% `surface/overlay/location-card`、12 pt 背景模糊、黑色 12%／y=6／blur=20 陰影；Primary Active「Start／開始」置左，Star、Copy、Close 命中範圍均至少 44 × 44 pt。卡片在最大 Dynamic Type 下依內容增高。
- 路線清單外框 Dark 使用 `surface/control`，選中列為 Light `surface/card`、Dark `surface/control/active`，並保留 primary 邊線。搜尋、最愛、GPX 清單共用 `GoFlyListRow` 與 `line/separator` token。
- 執行指示卡的標題、說明、箭頭改用動態 `text/primary`、`text/secondary`，icon 底使用 `surface/control`，避免 Light 下白字落在淺色面板；面板與 Tab Bar 使用同一 `surface/overlay/sheet` token。地圖控制在地點卡上方仍可見；MapKit Dark 外觀使用 muted／flat 與隱藏 POI，外觀偏好透過環境值更新原生地圖。
- 以上為 App 實作與 Simulator 截圖驗證。完整 fixture 矩陣輸出 64 個支援 frame 的 Light／Dark 共 128 張到 `work/gofly-ios-figma04/screenshots/`，並排頁為 `work/gofly-ios-figma04/screenshots/index.html`；執行指示卡修正後重拍 D6、D7、D10、D10.a、E2、E2.a、E4、E5 的兩種外觀。MapKit 原生地圖的道路、地名與 POI 細節不能逐像素重現 Figma 靜態 `Map / Base`。B4、B5、C1、D6 的 fixture 內容與設計畫面不同，分別由後續 B、C、D 頁票校準；Figma 只讀，未做實機驗證。

## 2026-10-28 MapControls 44 pt 納入 Light Icon Button（Figma 更新；App 待實作）

- 將 04「未定義」區的 `未定義 · MapControls · 44 pt 控制組` 移入 `Light · 0 · 共用元件（按鈕）` 的 B `ICON BUTTONS / Type × State × Size`，作為 `Type=MapControls, State=Enabled, Size=Large`，尺寸 44 × 44 pt；原未定義區展示與標籤已移除。
- Variant 使用白色圓形底（`color/surface/card`，`#FFFFFF`）、無邊框；置中引用 `0 · 共用元件（Icon）` 的 `icon/locate`，44 pt 時 glyph 為 22 × 22 pt。背景與 icon 均設為水平／垂直 Scale constraints，保留來源控制組的兩層陰影。
- 驗收：Light B 區只有一個 MapControls Large Enabled variant；44 × 44 pt 時 icon 與圓底中心重合；將元件縮放至 32 × 32 與放大至 64 × 64 pt 時，底與 icon 同步縮放且維持置中，並已還原 44 × 44 pt。Light 按鈕板與「未定義」區截圖、節點讀回確認。這是靜態 Figma wireframe 更新，未修改 App、未新增 prototype wiring，未完成裝置驗證。

## 2026-10-28 Dark MapControls 44 pt 納入共用 Icon Button（Figma 更新；App 待實作）

- 在 04 `Dark · 0 · 共用元件（按鈕）` 的 B `ICON BUTTONS / Type × State` 新增 `Type=MapControls, State=Enabled` 44 × 44 pt variant。Dark `Button / Icon` component set 共 13 個 variants：原六種 Type 各有 Enabled／Disabled，MapControls 目前只有 Enabled。
- 外觀沿用 Dark UI 的 `Dark · Recenter`：`color/surface/control` `#3A3A3C` 圓底、0.5 pt `color/line/separator` `#38383A` 邊框、兩層浮動陰影；`color/icon/primary` `#E5E5EA` locate 圖示 22 × 22 pt 置中。圖示容器與內部向量設 Scale constraints。
- 驗收：Dark B 區顯示 MapControls · 44 pt 標籤；44 × 44 pt 時 locate glyph 與底色同心。元件縮放至 32 × 32 與 64 × 64 pt 時，glyph 分別變為 16 × 16 與 32 × 32 pt 並保持置中，最後恢復 44 × 44 pt。Dark 按鈕板與 variant 截圖及節點讀回確認。此為靜態 Figma wireframe 更新，未修改 App、未新增 prototype wiring，未完成裝置驗證。

## 2026-10-28 路線清單 grip UI 外框角色（Figma 更新；App 待同步）

- Light `color/border`：`subtle=#E5E5EA`、`default=#C7C7CC`、`strong=#8E8E93`、`focus=#007AFF`。Light 色票已同步更新；Dark `color/border` 為 `subtle=#38383A`、`default=#48484A`、`strong=#8E8E93`、`focus=#0A84FF`，其中 default 保留原值，strong 與 default 有明顯差異。
- 路線清單外卡沿用 `subtle`；一般清單列使用 `default`，被 grip 抓取的列使用 `focus`，表示新順序的空位使用 `strong`。Light 與 Dark 的 `strong` 都必須明顯有別於各自的 `default`。D1／D2／D8／D9 Light 與 Dark 畫面已按此語意統一列框；D8 原錯用錯誤紅色的選中列改為 focus。
- 新增 Light／Dark `D2 · 路線規劃 / 拖曳排序示意` 靜態 wireframe，呈現被抓取列、一般清單列及 strong 新順序位置框。它只補充 D1／D2 面板中的 grip UI，不代表全螢幕可編輯路線清單已有 wireframe；沒有新增 prototype wiring。
- 驗收：Light 色票文字與色塊值一致；一般列框為 `#C7C7CC`、抓取列為 `#007AFF`、新順序位置框為 `#8E8E93`，strong 與 default 可直接分辨；外卡為 `#E5E5EA`。Dark 一般列框為 `#48484A`、新順序位置框為 `#8E8E93`，strong 與 default 有明顯差異，並使用對應 Dark token。D1／D2／D8／D9 與 Light／Dark D2 拖曳排序示意均已截圖讀回核對。
- App SwiftUI 尚未套用這次色彩角色映射，未做裝置驗證。

## 2026-10-29 Route Mode 與設定 UX 更新（Figma 更新；App 待實作，無實機驗證）

- 路線「＋ 新增停靠點」：新空欄位加在清單**最後**並成為終點，原終點保留原值並降為最後一個停靠點（取代先前「插在終點前」）。規劃面板與全部點位清單頁行為相同；新增後選取並捲至新欄位，空終點不規劃，回填後才重規劃。App 已依票 10 實作並以 simulator fixture 驗證；未做實機驗證。
- 無法規劃路線（D8，Light／Dark）：toast 按鈕「修正」。按下後系統自動重新安排**全部**地點順序（含起點）並重新規劃；找到可行順序即採用，找不到維持原順序與 toast。連線錯誤維持「重試」。App 已實作（issue 11）：無單次請求上限（每個有向地點對最多請求一次並快取）、4,096 個排序前綴，最多涵蓋 27 個地點；超出搜尋額度視為未找到，原草稿保留；編輯會取消搜尋。
- StatusPill 尺寸（2026-10-31 使用者指示）：寬度隨文字長度自動改變（hug），從外緣量左右留白 12 pt、上下留白 4 pt（高 26 pt，原 30 pt、左右 16 pt）。Figma 04 頁面的 Light／Dark StatusPill 主元件與頁內 78 個 instance 已統一；App 的 `GoFlyStatusPill` 已改，修正路線 sheet 的狀態 pill 也已對齊 Figma（sheet 高 242 pt）。單元測試通過、模擬器建置成功，未實機驗證，現有 UI 測試截圖需重拍。
- 修正路線 sheet（D8.a／b／c，Light／Dark，2026-10-31 設計稿新增，App 已實作於 `GoFlyRouteRepairSheet`，單元測試通過、未實機驗證）：按「修正」後以底部 sheet（含半透明遮罩，不用 toast）呈現。2026-10-31 依 Dark 版：sheet 高 242 pt，頂部為狀態 pill（修正中／修正完成／部分失敗）取代標題文字，Light 已對齊，App 的 sheet 仍用標題文字，待對齊。內含標題與進度條。進行中顯示「已嘗試 N／上限 段」：按鈕「取消」＋「完成」（disabled）；成功顯示「已成功 N／N 段」：「取消」＋「完成」（active，採用新順序）；失敗顯示「已成功 9／12 段」，進度條（primary 色）只計成功段數，按鈕「取消」＋「刪除失敗地點 (N)」，N 為將刪除的地點數。D8 失敗狀態下，底部 primary 按鈕由「開始」改為「修正」，與 toast 的「修正」同功能。按鈕下緣距 sheet 底 40 pt；取消保留原順序並回到 D8 失敗 toast；修正期間底層「開始」停用。修正搜尋的單段規劃只試「步行」一種交通模式（App 已實作，`RoutePlanning.planWalking`，未實機驗證）。
- 設定服務卡（F1／F1.a／F1.b，Light／Dark）：永遠只有一顆主按鈕：正常已停止＝「啟動模擬」、運行中＝「停止服務」、停止失敗或服務卡住＝「重置連線」；重置成功後按鈕變「啟動模擬」，導覽列下方懸浮出現 success toast（疊在內容上方、不推動版面）（標題「已重置連線」、說明「可以重新啟動模擬」）。新增 Figma frame `F1.b · 設定首頁 / 重置成功`（Light `322:51696`、Dark `322:51847`，位於 F1.a 右側）；取代 2026-10-26 一節中獨立「重置」第二顆按鈕的描述。App 已於票 16／17 實作完成，導覽列統一為 `GoFlySheetNavBar`（置中標題、`< 地圖` 藍色返回鈕、無 iOS 18 toolbar 圓形膠囊邊框），並透過 `bash app/GoFly/scripts/check.sh` 與 UI 截圖／最大 Dynamic Type 測試完成軟體驗證；未做實機驗證。
- 此為 App 實作與規格同步完成，未做實機驗證。

## 2026-10-30 設定與子頁 UI/UX 更新（Figma 04 更新；App 代碼已處理）

- **F1 設定首頁（Light `121:53504`、Dark `322:41217`）**：
  - 移除大字「設定」（NavBar 導覽列已有置中 title「設定」）。
  - 設定選單圖示（Settings menu icons）比照 App 設計：統一採用藍底圓角矩形徽章（`color/action/primary/surface`，圓角 7 pt）搭配白色反白圖示（`color/icon/inverse`）；「背景執行」列圖示統一為 Terminal 命令列提示符圖示（`icon/terminal`，造型為 `>_`，已新增至 `0 · 共用元件（Icon）`），其餘定位（`icon/nav`）、VPN（`icon/shield`）、語言（`icon/globe`）、外觀（`icon/moon`）、裝置（`icon/phone`）同步對齊。
- **F1.a 設定首頁 / 停止失敗（Light `239:15235`、Dark `322:41346`）**：
  - 頂部懸浮 danger toast（`Toast / 系統訊息 / danger（懸浮）`，位於導覽列下方 `y: 108`），標題「停止服務失敗」、說明「請檢查 VPN 通道後重試。」，toast title 與 text 內容精簡至 2 行以內，附帶「重試」與關閉按鈕。
- **F1.b 設定首頁 / 重置成功（Light `322:51696`、Dark `322:51847`）**：
  - 重置成功 success toast 改放在畫面下方懸浮，距底邊框 40 pt（`y: 745`，高 67 pt，距 852 底部邊界剛好 40 pt）；Figma 04 說明文字同步更新。
- **F6.a 設定 › 背景執行 / 背景運行時間 sheet（Light `238:9408`、Dark `322:41319`）**：
  - 移除 sheet bg cover（無背景暗色遮罩 / scrim）。
  - input style 比照 Figma 設計（雙滾輪 hr、min 搭配固定單位與冒號），下方配置「完成設定」主要按鈕。
- **F7 設定 › 語言（Light `123:59019`、Dark `322:41278`）**：
  - 移除語言清單上方小字（Section Header），只顯示語言選項清單。
- **0 · 共用元件（Icon）全數 Outline Stroke**：
  - 04 `0 · 共用元件（Icon）`（section `256:17781`）目錄下全數 53 個功能圖示（`icon/*`）均已完成 Outline Stroke 轉為向量填色路徑（`Vector (Stroke)`，無描邊 `strokes: []`，填色綁定 `color/icon/primary`、`color/icon/secondary` 等語意 token），解決描邊在縮放及主題覆寫時填色／描邊不一致的問題。
- 此為 Figma 04 渲染畫面與規格同步更新，代碼已由工程端處理完成。

## 2026-10-29 票 01：App Theme 色彩 token 對齊 Figma 04

- **Figma 設計**：只讀回 04 的 `GoFly iOS / Light Theme`、`GoFly iOS / Dark Theme`、`GoFly iOS / Common Color` Variables，未修改 Figma。Light／Dark 各有 88 個同名 Theme tokens，Common Color 有 14 個；全部原名與值保存於 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json) `colors.figmaVariables`。Dark 四階 surface 為 `#0B0B0D`、`#1A1A1C`、`#2C2C2F`、`#48484D`；Light 為 `#EEEEF3`、`#FBFBFD`、`#DEDEE4`、`#B9B9BF`。
- **App 實作**：`GoFlyCore/GoFlyColorTokens.swift` 保存每個 Figma path 的 Light／Dark／Common 值；`GoFlyThemeColor` 以 dynamic UIColor provider 轉成 SwiftUI Color，跟隨 `.preferredColorScheme`，`GoFlyStyle`／`GoFlyTextColor` 只提供語意角色別名。主要動作使用 Figma Primary surface。Dark primary 按鈕文字與圖示固定純白，依本輪使用者決定覆寫 Figma `color/action/primary/text` 的 `#E5E5EA`。
- **系統色例外**：`GoFlySearchPanel.swift` 的 `UITextField` label／clear-button 色及 `UIPasteControl` 背景保留 UIKit 系統控制外觀；`GoFlyGPXPreview.swift` 的 MapKit route renderer／marker tint 保留 MapKit 原生色。GoFly 自繪介面、MapNode、路線線條、位置箭頭與陰影均使用 Theme/Common Color tokens。
- **快照差異**：舊 `colors.primitive`／`colors.themes` 保留先前色票整理欄位，部分狀態 `main`、Info 與 overlay 欄位沒有現行 Figma Variable path，且數值與 Variables 不一致；不可作為 Swift token 來源。Dark Color Scheme 色票板部分表面值與現行 Theme Variables／本輪階梯決定不一致；本票不修改 Figma，後續色票板同步另行處理。
- **外觀與驗收**：Appearance 偏好仍由 `GoFlyPreferences.colorScheme` 即時套用；token 測試逐項對照 88×2 Theme 與 14 Common values，並驗證切換 palette。此票不改命令、送點、ACK 或背景語意。UI fixture Light／Dark 截圖位置與比對結論見票單執行紀錄；**未做實機驗證**。

## 2026-10-29 D5 新增「使用目前位置」列並改為輸入為空狀態（Figma 更新；App 既有行為）

- 04 D5 Light／Dark（`121:52709`、`322:40581`）改為搜尋欄輸入為空：游標＋貼上鈕、無清除鈕（與 B3 同款），清單最上方新增一列「使用目前位置」（`icon/nav`），下方為「最近搜尋」與「清空記錄」；D5 說明文字同步。規則（使用者確認）：只有輸入為空時才顯示「使用目前位置」與「最近搜尋」；輸入文字後改顯示搜尋結果。App 已是此行為；未做實機驗證。
- 2026-10-30 D1／D5 App 對齊：Figma D1 Route list 外卡 Light 綁 `color/canvas`（`#EEEEF3`）、Dark 綁 `color/surface/control`（`#2C2C2F`）；選中列 Light 為 `surface/card`、Dark 為 `surface/control/active`，primary 邊線保留。新增停靠點採 `color/text/accent`。D1 底部收藏按鈕依目前 56×56 共用 Icon Button instance：Light `surface/control/floating`（解析為 `#FBFBFD`）與 `line/border`，Dark `surface/card` 與 `line/separator`，star icon 28 pt；此項取代舊文件中「`#EEEEF0`、無邊」描述。D5 空 query 不顯示 placeholder；fixture 預置一筆「台北車站」最近搜尋，與「使用目前位置」列並排驗收，VoiceOver 仍以選中欄位名稱標示輸入框。上述為 Figma 設計與 App 模擬器截圖驗證；未做實機驗證。
- 2026-10-30 D5 樣式／間距補充：Favorite 使用共用 Primary Icon + Text inline button（star＋`Favorite`）；Role chip 上下外距 16 pt、使用目前位置列至後續清單下距 16 pt、最近搜尋列上下內距 8 pt。「使用目前位置」列與最近搜尋共用 list row 排版，放在 card 色圓角卡片中，icon 不加圓形 tile。D1 focused row 的 primary 邊線圓角與 list card 相同（14 pt）。共用地圖 StatusPill 與其上方搜尋列／執行標題的垂直間距統一為 12 pt。間距按 4 pt 規則整理；本次為 App 實作與規格更新，Figma 未修改。

## 2026-10-29 R05 連線說明精簡（Figma 渲染為準；App 已更新）

- 04 R05 Light／Dark 渲染為精簡版：導覽列「返回／連線說明」、三列單行步驟卡（下載 LocalDevVPN ›、開啟 LocalDevVPN ›、點 Connect）、「仍然無法連線？」一則提示卡；無大標題、副標、步驟說明小字、底部主按鈕與「本機網路權限」列。原 R05 說明文字與渲染衝突，已依渲染更新。App 依三語文案與共用步驟列實作此結構；步驟 1／2 保留 App Store 與 LocalDevVPN 開啟 fallback，返回後自動重新檢查 VPN。App 未提供原本的「本機網路權限」直達系統設定入口，目前未找到其他直接入口，需產品決定是否另設；未做實機驗證。

## 2026-10-29 Toast 一律懸浮（Figma 規格；App 已部分更新）

- 所有 Toast／Banner 以共用 overlay 疊在導覽列或搜尋列下方（左右 16 pt）、不推動版面；Figma Light／Dark Toast 使用黑 18%、y 4、blur 16 浮層陰影；多筆提示垂直堆疊、個別關閉。App 已將地圖、首次引導、設定首頁與子頁及搜尋輸入警告放進浮層 overlay；操作面板內的操作狀態內容仍留在其所屬面板。Snackbar 維持底部懸浮；未做實機驗證。

## 2026-10-29 R04、Dark Map 與 Toast 回讀（Figma 04 渲染為準）

- **Figma 渲染**：只讀 Light／Dark R04（`121:51246`／`322:40124`）、R05（`123:56962`／`322:40160`）及 B1（`121:51314`／`322:40269`），沒有修改 Figma。R04 是四列單行步驟卡、中間狀態 pill、連線說明 link、單一底部「檢查連線」CTA；R05 是返回列、三列步驟卡與一張 troubleshooting 卡。
- **App 實作**：R04 頁底 Light `canvas #EEEEF3`／card `#FBFBFD`，Dark `canvas #0B0B0D`／card `#1A1A1C`；VPN 檢查成功後沿用 controller 的再次檢查，成功即進入 B1 並收合 sheet，不顯示成功 Toast；失敗 Toast 疊在內容上方。R05 使用三列精簡說明並在返回後自動重查；步驟 1／2 保留原外部連結行為。
- **Map**：Dark B1 的 Sheet 與 Tab Bar 在 App 中引用同一個 `surfaceOverlaySheet` token，Dark／Light 均採 95% alpha。MapKit Dark 設為 flat／muted 標準配置並排除 POI，Light 設回 default 標準配置；偏好外觀更新時重新套用。MapKit 沒有 API 將底圖每種地物精確設成 Figma `color/map/*`，故底圖為近黑低飽和近似；路線、Pin、箭頭與自繪標註維持 Dark tokens。
- **設定缺口與驗證界線**：精簡 R05 移除唯一發現可直接開啟「本機網路權限」的列；App 目前沒有替代入口，需產品決定是否另設。UI fixture 截圖為 simulator 軟體驗證；未做實機驗證。R06 未見於目前 frame catalog；R07／R08 需要 Setup identity／pairing transaction，沒有宣稱截圖通過。

## 2026-10-29 STATUS Toast 元件與首次設定成功流程更新

- **Figma 設計（只讀）**：讀取 `Light · 0 · 共用元件: STATUS · BANNER / SNACKBAR / PILL` 的 Light／Dark Toast danger、warning、success 實例。Success 顯示 outline check-circle、14 pt 圓角、361 pt 寬、12／14 pt 內距、22 pt 圖示、15／13 pt 標題與說明、20 pt 關閉符號；陰影為黑 18%、y 4、blur 16。Dark success 的 surface 是 `#1B2E22`，外框與圖示為 Figma 綁定的 `color/icon/success` `#6FC48B`。這與 token `color/line/status/success` Dark `#52A072` 不同，未修改 Figma；App 依元件實際綁定與渲染使用 icon token。
- **App 實作**：共用 `GoFlyStatusBanner` 改用 outline 狀態圖示、對應 token、14／12 pt 內距與 44 pt 關閉命中區；R04 VPN 成功時不顯示 success Toast，檢查成功後自動再次確認並進入 B1，首次進入時 sheet 收合。失敗通知仍用共用浮層。
- **行為差異**：Figma R04 靜態畫面仍呈現「檢查連線」按鈕，沒有描述成功後自動導覽；自動進入 B1 是本輪使用者確認的 App 行為。Figma 保持不變。模擬器 screenshot fixture 用 deterministic VPN probe 驗證；未做實機驗證。

## 2026-10-29 R04 標題位置與字體回饋

- **Figma 設計（只讀）**：R04 Light 標題圖層 `121:51267` 位於 x=16、y=130，框 361×39 pt；文字樣式為 28 pt Semibold（`Theme/display`）。
- **App 實作**：移除 R04 標題前多餘的垂直留白，標題回到 Figma y≈130 的位置，使用 28 pt Semibold 的共享 display role；UI test 檢查 Light／Dark 位置與標題框高度。字體限定為系統字體；02 Typography 票將把字級 token 全面統一到 `Font.system` 並與 Figma Theme 樣式對應。
- **驗證界線**：更新後 Light／Dark 模擬器截圖為 `work/gofly-ios-figma04/screenshots/R04-light.png` 與 `R04-dark.png`；未做實機驗證。

## 2026-10-30 STATUS Toast 雙色圖示與系統遮罩（App 實作）

- **Figma 設計（只讀）**：Light／Dark `0 · 共用元件 / STATUS · BANNER / SNACKBAR / PILL` 中，Toast 實際使用帶 status surface 填色、status icon 描邊的雙色向量；danger／warning 為 `icon/alert`，success 為嵌在 Toast 元件內的 `icon/okfill`。`icon/okfill` 不是獨立的 53 個 `icon/*` 之一。Danger 實例為 361 × 85 pt：圖示 22 pt；文字欄 x=47、寬 203、高 59 pt（標題 15 pt／21 pt 行框、說明 13 pt／兩行共 36 pt）；action x=260、56 × 32 pt；關閉 glyph x=326、20 × 20 pt。Overlay／Dim 在 Light 綁 `#1C1C1E` @ 40%，Dark 綁 `#000000` @ 40%。
- **App 實作**：新增 `status-toast-danger|warning|success` 向量資產，各含 Figma Light／Dark 外觀版本，並由 `GoFlyIcon` 呈現原始雙色；共用元件展示頁使用對照用的三種 Toast 文案與按鈕。為符合系統字體下兩行說明的 85 pt Figma 渲染高度，`GoFlyStatusBanner` 增加說明行距並調整標題最小行框及垂直布局；action／close 維持至少 44 × 44 pt 命中區。一般 53 個單色 icon catalog 與已實作的 R04-success 自動進 B1（不顯示 Toast）保持原設計行為。系統 sheet 的 root 補光依外觀取 Light `common/gray/950`、Dark `common/black`，以 20% 與 iOS 原生 dim composition，避免遮罩過深；Sheet／ActionSheet／share sheet 都使用同一狀態追蹤。
- **驗證界線與剩餘差異**：Light／Dark 元件圖與 Sheet scrim 截圖為 simulator fixture，見 `work/gofly-ios-figma04/screenshots/ticket04-feedback/`；Figma Toast 原圖為 `work/gofly-ios-figma04/figma/Toast-{light,dark}-{danger,warning,success}.png`。App 使用 `Font.system` 後，danger Toast 說明比 Figma 早一個字元換行；外框 85 pt 與 action／close 幾何已對齊。B7、B10、D8、F1.b 的情境 fixture 嘗試記錄於票 04：iPhone 17 Pro／Pro Max 模擬器在 B7 fixture 停留 launch screen，XCTest 未取得 fixture，因此本輪沒有新的情境截圖，不將前一輪截圖當成本輪驗收。系統 sheet gallery 只比 dim 強度，內容不等同 C2；未做實機驗證。

## 2026-10-30 Figma 04 UI 修訂（取代對應舊規則）

- **A 區**：R02、R03、R04、R04.a 移除頂端步驟 progress UI；R08 identity mismatch 頁移除「重試」按鈕，因安裝套件不符只能由 Mac App 重新安裝／修復。這是靜態設計與 App UI 更新；R08 不代表裝置可自行重試安裝。
- **B 區共用提示**：B6 成功 Snackbar 右側加入 X 關閉按鈕；所有 Toast 元件的訊息／action／X 相鄰間距統一 8 pt，Dark 所有 Toast 的說明小字與 X 均使用 primary 文字／圖示色。地圖 MapControls 與 panel 間距統一 16 pt。D17 GPX 成功提示改用 X 關閉，不再用「載入」action；提示與匯入按鈕保留 16 pt 間距。
- **C2**：移除輸入欄上方獨立「標籤」文字，欄位 placeholder 保留「標籤」；儲存按鈕下緣至 sheet 底部留 40 pt。
- **D 區**：D4 LocationCard 主按鈕改為「確認」。D5 最愛入口使用無底色的 icon＋文字 Ghost 按鈕；繁中／簡中同時顯示「最愛／最爱 Favorite」，英文顯示「Favorite」。搜尋欄至 Role／Favorite 列間距 12 pt、Role／Favorite 列至「使用目前位置」16 pt、「使用目前位置」至最近搜尋標題 16 pt、最近搜尋標題至首列 8 pt。D8 只要不是連線／裝置 admission 阻擋，Start 不因非連線錯誤而 disabled；端點無效仍不可開始。D10 中斷恢復面板主按鈕文案為「繼續」，沿用既有連線修復／恢復行為。D19–D22 導覽列 action 使用 Primary 文字色，勾選 icon action 改為「選取」文字按鈕（依 C1）；D23 清單卡至新增／反轉按鈕間距為 12 pt。
- **40 pt 底部間距**：R02–R04.a 以外的本次指定頁面中，D6、D7、D10、D10.a、D11、D17、D18、D20、E2、E3 的底部主要按鈕下緣至所屬 sheet／panel 底部統一留 40 pt；這只覆蓋列出的畫面，不把 40 pt 擴大成所有 sheet 的全域規則。
- **E1／Joystick**：E1、E1.a、E2、E2.a、E3 的 panel 與 grabber 使用一致 96% opacity，Light／Dark 結構相同。Figma Joystick 維持分組的 `compass` 底圖與 `knob` 控制層；App 以可互動 knob 疊在 compass base 上，兩者依 Light／Dark Theme tokens 呈現。
- **狀態**：本次 Figma 變更僅更新 wireframe，不含 prototype wiring。SwiftUI、三語文案、測試與本文件已同步修改；`app/GoFly/scripts/check.sh` 通過 359 tests／58 suites、Native handoff host tests 與 unsigned simulator build。指定的 UI XCTest 未進入執行：`CODE_SIGNING_ALLOWED=NO` 建置出的 `GoFly.app` Info.plist 缺少 `CFBundleIdentifier`；依使用者要求，暫留待與新項目合併處理。未做實機驗證、未 commit。

## 2026-10-31 使用者清單：Figma 設計稿更新

以下為 04 頁面（Light／Dark）的設計。iOS App 已依此開發（見文末「App 實作狀態」），單元測試通過、模擬器建置成功，未實機驗證。

- **全部地點（D23）**：列左側為拖曳握把（取代序號，可拖曳排序；App 與路線面板共用 `GoFlyRouteNodeCard`／`GoFlyRouteNodeTitleText`／`GoFlyRouteNodeDeleteButton`，但不顯示角色小字、列高 46）；空白地點的提示字用較淺的 disabled 文字 token；每列右側改為 ✕ 刪除（移除「起點／停靠點 N／終點」label）；右上文字按鈕改為「清除」（刪除所有地點；原「選取」入口取代）；「反轉順序」為 Ghost Secondary。路線清單有 2 個以上地點時，起點與終點的 ✕ 為「刪除該地點」，不是清空。
- **規劃路線 card sheet（D24.a–d，新增）**：按「開始」後不可無反應，改以底部 sheet 顯示規劃狀態。規劃中：pill 灰色「規劃中」，主按鈕「進行中」（disabled）；成功：pill 綠色，主按鈕「完成」，成功後自動開始；部分成功：pill 紅色，主按鈕「刪除失敗地點 (N)」，刪除後自動開始；全部失敗：pill 紅色，主按鈕「清空地點」。皆有「取消」。D8.a–c 為「修正」流程，D24 為「開始」流程。
- **Location card**：主按鈕寬度隨內容自適應（hug），左右內距固定 12；星號開啟 label sheet（已收藏者右上有「刪除」，未收藏者無，見 C2／C2.a）；複製座標 toast 底緣距 card 上緣 8（B5.a）。
- **最愛路線（D19–D22）**：底部搜尋列移除貼上按鈕。最愛地點（C1）維持貼上；是否共用同一搜尋列元件，待 App 實作時確認。
- **地圖**：路線線色改為較淺的 primary 藍（Light #4DA3FF、Dark #66B3FF），不再有白邊（casing 隱藏），已走過的段落 55% 透明；起點／停靠點／終點圖示統一為白底圓 + primary 色（含 Dark，不再用黑圈）。
- **速度 sheet（D7）**：預設速度 chip 與滑桿間距改為 24。
- **設定**：背景運行時間 sheet 移除標題，時間輪盤需支援拖曳連續滾動（行為待開發）；裝置與簽名移除「到期前請在 Mac App…」小字。
- **Ghost Secondary**：「檢視路線」與「反轉順序」為 Ghost Secondary；瞬移「查看全部」目前是 BottomSheet 元件內的次要色文字，不是獨立按鈕元件，待 App 統一。

### App 實作狀態（2026-10-31）

- 已實作：全部地點 ✕／清除（danger 色）與路線列 ✕ 在 2 個以上地點時刪除起終點；Ghost Secondary（瞬移「查看全部」、全部地點「反轉順序」）；Location card 主按鈕 hug＋左右 12、星號 sheet 對已收藏者顯示刪除、複製 toast 距 card 上緣 8（card 高 180）；路線線色 `color/map/route`（Light #4DA3FF／Dark #66B3FF）、起終點／停靠點圖示統一 primary 環＋白底；速度 sheet chip 下間距 24；背景運行時間 sheet 無標題、改為可連續拖曳的滾輪；裝置與簽名移除小字；最愛路線搜尋列移除貼上；規劃路線 card（D24，`GoFlyRouteStartSheet`，開始時逐段規劃；成功自動開始、部分成功刪除失敗地點後自動開始、全部失敗清空地點）。
- Light `color/icon/warning` 由 #B85C00 改為 #E39A18（狀態 pill 的警告圓點）。
- 最愛路線與最愛地點共用 `GoFlyFavoritesBottomBar`，僅以 `showsPasteControl` 區分。
- 尚未做：規劃中 sheet 在 0.4 秒內完成時不顯示（避免閃現）；成功狀態因自動開始，實際不會停留；UI 測試截圖需重拍；未實機驗證。
- 設定（2026-10-31 使用者指示，App 已改、設計稿 F6／F5 尚未同步）：背景執行頁刪除「背景延續」狀態卡（`GoFlyContinuationStatus` 不再顯示）；時間輸入只保留一個背景色，不再另畫選取列的 pill 底（系統滾輪自身的選取樣式不受控）；VPN 通道頁與引導頁的英文按鈕改為「Open LocalDevVPN」（中文原本已是「開啟 LocalDevVPN」）。
- 路線執行（2026-10-31 使用者指示，App 已改、設計稿尚未同步）：來回開啟時，進度條上方標籤由「目前路線位置」改為「自動來回 (順向)」／「自動來回 (逆向)」，隨目前行進方向變化；來回關閉時仍顯示剩餘時間。
