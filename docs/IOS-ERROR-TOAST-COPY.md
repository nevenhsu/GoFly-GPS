# GoFly iOS 錯誤 Toast 文案、按鈕與處理架構

2026-10-25 基線；2026-10-30 依 Figma D8／票 11 更新路線規劃失敗文案與 action。對應 [IOS-STATUS-ERRORS.md](IOS-STATUS-ERRORS.md) 的 77 項。按鈕 `—` 表示不放主按鈕，只留關閉（×）。

## 1. Toast action

| 按鈕 | 繁中 | English | 行為 |
| --- | --- | --- | --- |
| **重試** | 重試 | Retry | 共用的「重設工作階段並重試」：重建 VPN 通道與裝置連線（既有 `ServiceController.resetTunnel`／`rebuildClientConnection`），成功後自動重跑剛才失敗的操作 |
| **修正** | 修正 | Fix | 僅用於路線規劃失敗；在固定搜尋上限內重排全部地點（含起點）並重新規劃，成功採用新順序，失敗保留原順序 |
| 設定 | 設定 | Settings | 只用於需要使用者親自在實機或 Mac App 處理的事（配對、開發者模式、裝置準備、儲存空間） |
| 選檔 | 選檔 | Choose File | 開檔案選擇器；GPX 錯誤與保存檔損壞（需重新匯入）共用 |

其餘錯誤**不放按鈕**，只留關閉（×）：文案已說明該怎麼做（選起點、選地點、移除一筆再試），使用者直接在原畫面操作即可。

## 2. 文案表

標題：App 級用「類別標題」，內文即下表文案。範圍欄：**A**＝App 級（全域），**P**＝頁面／資料級，**M**＝模式級。

### 連線與裝置服務（A，類別標題：裝置連線問題／Device connection issue）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `error.pairingRequired` | 缺少配對資料。請將這部 iPhone 連接 Mac App，完成裝置準備。 | Pairing data is missing. Connect this iPhone to the Mac app to finish device setup. | 設定／Settings |
| `error.identityMismatch` | 配對資料屬於其他裝置。請將這部 iPhone 連接 Mac App 修復。 | Pairing data belongs to a different device. Connect this iPhone to the Mac app to repair it. | 設定／Settings |
| `error.developerModeRequired` | 請在這部 iPhone 開啟開發者模式，再連接 Mac App 完成裝置準備。 | Turn on Developer Mode on this iPhone, then connect to the Mac app to finish setup. | 設定／Settings |
| `error.devicePreparationRequired` | 這部 iPhone 需要裝置準備。請連接 Mac App 完成準備。 | This iPhone needs device setup. Connect to the Mac app to complete it. | 設定／Settings |
| `error.serviceUnavailable` | 無法連接裝置服務。請檢查 VPN 通道；若仍無法連接，請在 Mac App 修復這部 iPhone。 | Can't reach the device service. Check the VPN tunnel; if it still fails, repair this iPhone in the Mac app. | 重試／Retry |
| `error.tunnelUnavailable` | 無法連接 VPN 通道。請確認 iPhone 已連上 Wi‑Fi（只用行動網路無法使用），重新連接 LocalDevVPN，再於 GoFly 重置 VPN 通道。 | Can't reach the VPN tunnel. Make sure the iPhone is on Wi‑Fi (cellular only won't work), reconnect LocalDevVPN, then reset the VPN tunnel in GoFly. | 重試／Retry |
| `error.operationTimedOut` | 裝置未在時限內確認操作。請檢查連線並停止服務後重試；GPS 恢復確認狀態另列於下方。 | The device didn't confirm in time. Check the connection, stop the service, then try again. GPS restore status is shown below. | 重試／Retry |
| `error.deviceRequired` | 需要已完成準備的實體 iPhone；模擬器無法啟動裝置服務或確認 GPS 恢復。 | A prepared physical iPhone is required. The Simulator can't start the device service or confirm GPS restore. | — |
| `error.storageUnavailable` | 無法讀取裝置設定資料。請檢查可用儲存空間，並在 Mac App 修復這部 iPhone。 | Can't read device settings. Check available storage and repair this iPhone in the Mac app. | 設定／Settings |

### 路線規劃與匯入執行（M：路線模式，類別標題：路線無法規劃／Can't plan route）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `route.error.missingStart` | 請選擇起點。 | Choose a start point. | — |
| `route.error.missingDestination` | 請選擇終點。 | Choose a destination. | — |
| `route.error.currentLocationUnavailable` | 目前位置尚無法確認。請在地圖或搜尋中，為使用目前位置的節點選擇地點。 | Your current location can't be confirmed yet. Pick a place on the map or in search for any stop that uses current location. | — |
| `route.error.planningFailed` | 找不到可通行的路徑。請重新檢查起點，或點選修正。 | No drivable route found. Check the start point or select Fix. | 修正／Fix |
| `route.error.invalidPath` | 規劃的路線無效。請重新選擇地點後再試。 | The planned route isn't valid. Choose the places again and retry. | — |
| `imports.execution.disconnectedSegments` | 各段端點未完全銜接。仍可預覽或匯出，但無法載入執行。 | Segment endpoints don't connect. You can still preview or export, but it can't be loaded to run. | — |
| `imports.execution.zeroDistance` | 路徑沒有可行進距離。仍可預覽或匯出，但無法載入執行。 | The path has no travel distance. You can still preview or export, but it can't be loaded to run. | — |

### 搖桿與漫步（M：搖桿模式，類別標題：搖桿無法使用／Joystick unavailable）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `joystick.error.originUnavailable` | 目前沒有已確認的可用位置。請設定起點後使用搖桿。 | No confirmed location is available. Set a start point to use the joystick. | — |
| `joystick.error.noCandidate` | 找不到新的目的地。請在地圖選點或重試。 | Couldn't find a new destination. Pick one on the map or try again. | 重試／Retry |

### 最愛地點（P，類別標題：最愛地點／Favorite places）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `favorites.error.corruptArchive` | 最愛地點資料已損壞，無法讀取。原有資料已保留。 | Favorite places data is damaged and can't be read. Your existing data was kept. | — |
| `favorites.error.unsupportedSchema` | 最愛地點資料版本不相容。原有資料已保留。 | Favorite places data is an incompatible version. Your existing data was kept. | — |
| `favorites.error.unsafeFile` | 無法安全開啟最愛地點。原有資料已保留。 | Couldn't safely open favorite places. Your existing data was kept. | — |
| `favorites.error.unavailable` | 目前無法使用最愛地點，請嘗試重新開啟 GoFly。 | Favorite places are unavailable. Try reopening GoFly. | 重試／Retry |
| `favorites.error.writeFailed` | 變更未能儲存，原有最愛維持不變，請再試一次。 | Changes weren't saved and your favorites are unchanged. Please try again. | 重試／Retry |
| `favorites.error.invalidPlace` | 無法收藏此地點，請選取有效地點後再試。 | Can't save this place. Choose a valid place and try again. | — |
| `favorites.error.invalidLabel` | 標籤請使用 120 個字以內。 | Use 120 characters or fewer for the label. | — |
| `favorites.error.limitExceeded` | 最愛地點已達儲存上限，請移除一筆最愛或縮短標籤後再試。 | Favorites are full. Remove one or shorten the label, then try again. | — |
| `favorites.error.notFavorite` | 此地點已不在最愛中，請重新加入後再儲存標籤。 | This place is no longer a favorite. Add it again before saving the label. | — |

### 匯入路線清單（P，類別標題：匯入路線／Imported routes）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `imports.error.corruptArchive` | 匯入路線清單已損壞，暫時無法變更。 | The imported routes list is damaged and can't be changed for now. | — |
| `imports.error.unsupportedSchema` | 尚未支援此匯入清單版本。 | This imported list version isn't supported yet. | — |
| `imports.error.unsafeFile` | 無法安全讀取保存的路線檔案，請重新匯入來源檔案。 | Couldn't safely read the saved route file. Re-import the source file. | 選檔／Choose File |
| `imports.error.unavailable` | 暫時無法讀取匯入路線，請再試一次。 | Imported routes can't be read right now. Please try again. | 重試／Retry |
| `imports.error.writeFailed` | 無法儲存變更，原清單已保留。請再試一次。 | Couldn't save changes. The original list was kept. Please try again. | 重試／Retry |
| `imports.error.limitExceeded` | 匯入清單已達儲存上限，請先移除不需要的路線。 | The imported list is full. Remove routes you don't need first. | — |
| `imports.error.invalidFilename` | 檔名不受支援，請重新命名來源檔案後再試。 | This file name isn't supported. Rename the source file and try again. | 選檔／Choose File |
| `imports.error.notFound` | 此匯入路線已不存在，請選擇其他路線。 | This imported route no longer exists. Choose another route. | — |
| `imports.error.metadataMismatch` | 保存的路線與清單資料不符，請重新匯入來源檔案。 | The saved route doesn't match the list data. Re-import the source file. | 選檔／Choose File |
| `imports.error.hashMismatch` | 保存的路線未通過驗證，請重新匯入來源檔案。 | The saved route failed verification. Re-import the source file. | 選檔／Choose File |
| `imports.error.noSelection` | 請先選擇已匯入路線。 | Select an imported route first. | — |
| `imports.error.busy` | 請等待目前檔案操作完成。 | Wait for the current file operation to finish. | — |
| `imports.error.nothingToUndo` | 目前沒有可復原的刪除路線。 | There's no deleted route to undo. | — |

### 最愛路線清單（P，類別標題：最愛路線／Favorite routes）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `favoriteRoutes.error.corruptArchive` | 最愛路線清單已損壞，暫時無法變更。 | The favorite routes list is damaged and can't be changed for now. | — |
| `favoriteRoutes.error.unsupportedSchema` | 尚未支援此最愛路線清單版本。 | This favorite routes list version isn't supported yet. | — |
| `favoriteRoutes.error.unsafeFile` | 無法安全讀取保存的最愛路線檔案。 | Couldn't safely read the saved favorite route file. | — |
| `favoriteRoutes.error.unavailable` | 暫時無法讀取最愛路線，請再試一次。 | Favorite routes can't be read right now. Please try again. | 重試／Retry |
| `favoriteRoutes.error.writeFailed` | 無法儲存變更，原最愛路線已保留。請再試一次。 | Couldn't save changes. Your favorite routes were kept. Please try again. | 重試／Retry |
| `favoriteRoutes.error.limitExceeded` | 最愛路線已達儲存上限，請先移除不需要的路線。 | Favorite routes are full. Remove routes you don't need first. | — |
| `favoriteRoutes.error.invalidLabel` | 標籤最多 120 字，且不能包含換行。 | Labels can be up to 120 characters and can't contain line breaks. | — |
| `favoriteRoutes.error.invalidPlace` | 路線地點資料無效，請重新選擇該地點後再儲存。 | A place in this route is invalid. Choose it again before saving. | — |
| `favoriteRoutes.error.tooFewValidPlaces` | 至少需要兩個有效地點。請先在地圖或搜尋中選擇地點。 | At least two valid places are needed. Pick places on the map or in search first. | — |
| `favoriteRoutes.error.notFound` | 此最愛路線已不存在。 | This favorite route no longer exists. | — |
| `favoriteRoutes.error.metadataMismatch` | 保存的最愛路線與清單資料不符。 | The saved favorite route doesn't match the list data. | — |
| `favoriteRoutes.error.hashMismatch` | 保存的最愛路線未通過驗證，無法載入。 | The saved favorite route failed verification and can't be loaded. | — |
| `favoriteRoutes.error.noSelection` | 請先選擇最愛路線。 | Select a favorite route first. | — |
| `favoriteRoutes.error.busy` | 請等待目前最愛路線操作完成。 | Wait for the current favorite route operation to finish. | — |
| `favoriteRoutes.error.nothingToUndo` | 目前沒有可復原的刪除路線。 | There's no deleted route to undo. | — |

### GPX 內容（P，類別標題：無法匯入 GPX／Can't import GPX）

13 項按鈕全部為 **選檔／Choose File**。

| 代碼 | 繁體中文 | English |
| --- | --- | --- |
| `gpx.error.invalidXML` | GPX 檔案的 XML 格式無效，請選擇其他檔案。 | The GPX file has invalid XML. Choose another file. |
| `gpx.error.unsupportedVersion` | 僅支援 GPX 1.1 格式。 | Only GPX 1.1 is supported. |
| `gpx.error.unsupportedNamespace` | 檔案未使用標準 GPX 1.1 格式。 | The file doesn't use the standard GPX 1.1 format. |
| `gpx.error.unsupportedEncoding` | 請將 GPX 檔案儲存為 UTF-8 或 UTF-16 後再試。 | Save the GPX file as UTF-8 or UTF-16 and try again. |
| `gpx.error.unsafeXML` | 檔案含不支援的 XML 宣告，請選擇標準 GPX 1.1 檔案。 | The file has unsupported XML declarations. Choose a standard GPX 1.1 file. |
| `gpx.error.invalidPoint` | 檔案含無效座標，整份檔案未匯入。 | The file has invalid coordinates, so nothing was imported. |
| `gpx.error.invalidParent` | GPX 點位未放在支援的群組中。 | GPX points aren't inside a supported group. |
| `gpx.error.mixedKinds` | 請將軌跡、路線或航點分別存為獨立 GPX 檔案後匯入。 | Save tracks, routes and waypoints as separate GPX files, then import. |
| `gpx.error.emptyGroup` | GPX 檔案含空白軌跡、區段或路線。 | The GPX file has an empty track, segment or route. |
| `gpx.error.tooFewPoints` | GPX 檔案至少需要 2 個有效點。 | A GPX file needs at least 2 valid points. |
| `gpx.error.pointLimitExceeded` | GPX 檔案超過 10,000 點上限。 | The GPX file exceeds the 10,000-point limit. |
| `gpx.error.sizeLimitExceeded` | GPX 檔案超過 2 MiB 上限。 | The GPX file exceeds the 2 MiB limit. |
| `gpx.error.resourceLimitExceeded` | GPX 檔案超過支援的結構上限。 | The GPX file exceeds supported structure limits. |

### Session 復原資料（P，類別標題：工作階段／Saved session）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `recovery.error.unavailable` | 無法存取已存工作階段，請檢查可用儲存空間。 | Can't access the saved session. Check available storage. | 重試／Retry |
| `recovery.error.unsafeFile` | 無法安全讀取工作階段檔案，原始資料已保留。 | Couldn't safely read the session file. Original data was kept. | — |
| `recovery.error.writeFailed` | 無法儲存變更，請檢查可用空間後重試。 | Couldn't save changes. Check free space and try again. | 重試／Retry |
| `recovery.error.corruptArchive` | 已存工作階段已損壞，原始資料未被取代。 | The saved session is damaged. Original data wasn't replaced. | — |
| `recovery.error.unsupportedSchema` | 不支援此工作階段格式，原始資料已保留。 | This session format isn't supported. Original data was kept. | — |
| `recovery.error.limitExceeded` | 工作階段超過支援的儲存上限，未儲存此次變更。 | The session exceeds the storage limit. This change wasn't saved. | — |
| `recovery.error.invalidSnapshot` | 工作階段資料無效，未儲存此次變更。 | The session data is invalid. This change wasn't saved. | — |
| `recovery.error.revisionExhausted` | 無法繼續儲存此工作階段，原始資料已保留。 | This session can't be saved any further. Original data was kept. | — |

## 3. 處理邏輯（從簡）

1. **能重試就只給「重試」**。重試 = 重設工作階段後重跑原操作，不讓使用者判斷該重置哪一層。連線類（`serviceUnavailable`、`tunnelUnavailable`、`operationTimedOut`）、存取／寫入失敗類（`unavailable`、`writeFailed`）都走這一條。Wi‑Fi 與路線規劃失敗的「重試」只重新檢查／重新規劃，不重置工作階段。
2. **重試失敗不加新 toast**，只更新原 toast；重試中按鈕顯示進行中並停用。連續失敗 2 次後，把按鈕換成「設定」。
3. **無法由 App 修復的**（配對、開發者模式、裝置準備、儲存空間）→「設定」。
4. **資料損壞、格式不支援、已達上限**：保留原檔，不重試、不自動修復，不放按鈕。
5. **輸入驗證**（沒選起點、沒選路線、標籤太長、忙碌中、無可復原）：欄位內提示或 2 秒 snackbar，不放按鈕、不讓 Pill 變紅。
6. **關閉 × 只是隱藏**，錯誤未解除時 Pill 仍是紅色；條件解除才恢復 Standby／Running／Paused／Stopped。
7. **同時多個錯誤只顯示一個**，優先序：App 級 → 資料 → 模式 → 驗證。

## 4. 架構（App 級／模式級）

只做兩件事：**一張表**和**一個彙整點**。

```swift
struct GoFlyIssue: Identifiable {
    let id: String              // 錯誤代碼，如 "error.tunnelUnavailable"
    let scope: Scope            // .app 或 .mode(.route / .joystick)
    let kind: Kind              // .blocking / .validation
    let action: Action?         // .retry / .openSettings / .chooseFile / nil
}
```

- **來源只回報**：`ServiceController`、`NetworkMonitor`、各 Store 回報 App 級；`RouteExecutionController` 回報路線模式級；`JoystickMovementController` 回報搖桿模式級。把現有的 `SessionStatusErrors` 直接演進成彙整點 `GoFlyIssueCenter`，不另起爐灶。
- **一張文案表**：錯誤代碼 → 標題／內文 key／按鈕。第 2 節的內容就是這張表；單元測試比對 77 項不漏、zh-Hant／en 都有。
- **按鈕動作**只有三個 enum case，`.retry` 一律呼叫共用的重設工作階段，各畫面不再自己寫重試閉包。
- **App 級**：常駐、任何模式都顯示在地圖頂部；資料類 blocked 時只讓 Pill 變紅，完整訊息顯示在該頁內。
- **模式級**：只在所屬模式顯示；切走隱藏、切回仍在（錯誤狀態屬 controller，不屬 view）。
- 取代現行 `GoFlyMapView.floatingSystemToast` 的 `if / else if` 鏈與各自的 `xxxDismissed` 旗標，改為由彙整點取最高優先的一個，dismiss 以錯誤 id 記錄。

## 5. 待確認

1. 驗證類（約 8 項）不計入 Pill 的 Error，會改動 [IOS-STATUS-ERRORS.md](IOS-STATUS-ERRORS.md)「77 項全為 Error」的規則，是否同意？
2. 連續失敗 2 次後換成「設定」，次數是否合適？
3. 與 Figma `04 · iOS Redesign` 的 Toast 變體尚未比對。
