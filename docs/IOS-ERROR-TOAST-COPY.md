# GoFly iOS 錯誤 Toast 文案、按鈕與處理架構

2026-10-25 基線；2026-10-30 依 Figma D8／票 11 更新路線規劃失敗文案與 action。對應 [IOS-STATUS-ERRORS.md](IOS-STATUS-ERRORS.md) 的 77 項。按鈕 `—` 表示不放主按鈕，只留關閉（×）。

## 1. Toast action

| 按鈕 | 繁中 | English | 行為 |
| --- | --- | --- | --- |
| **重試** | 重試 | Retry | 共用的「重設工作階段並重試」：重建 VPN 通道與裝置連線（既有 `ServiceController.resetTunnel`／`rebuildClientConnection`），成功後自動重跑剛才失敗的操作 |
| **修正** | 修正 | Fix | 僅用於路線規劃失敗；在固定搜尋上限內重排全部地點（含起點）並重新規劃，成功採用新順序，失敗保留原順序 |
| 設定 | 設定 | Settings | 只用於需要使用者親自在實機或 Mac App 處理的事（配對、開發者模式、儲存空間） |
| 選檔 | 選檔 | Choose | 開檔案選擇器；GPX 錯誤與保存檔損壞（需重新匯入）共用 |

**連線類失敗（`error.tunnelUnavailable`、`error.serviceUnavailable`、`error.operationTimedOut`）不再有自己的 toast**：地圖、操作面板與服務設定頁一律只顯示連線檢查的那一張（Wi‑Fi／區域網路／VPN，依序判斷），同時間不再出現其他錯誤 toast；操作面板只保留「連線無法使用」標題與重試／取消。下表這三筆文案目前沒有畫面使用，保留供內部錯誤碼與日誌。未在真機驗證。

**同一失敗只留一張 toast**：操作失敗（`preparedOperationFailed`，有重試）顯示時，或搖桿／路線模式的錯誤 toast 已在報告同一個錯誤碼時，不再同時顯示 App 級通用服務錯誤 toast（`serviceError`）；只保留一張。尚未在真機驗證。

**`error.devicePreparationRequired`（2026-11-03 實作文案）**：實機確認（iPhone 15 Pro，27.0.1 → 27.2）裝置支援只在 iOS 更新後失效，一般重開機不受影響；用 USB 接上裝有 Xcode 的 Mac 後，Mac 會在背景自動重新掛載，按重試即可恢復。toast 文案引導用 USB 連接 Mac 並用 Mac 端安裝工具（GoFly Mac App 或 iloader）重新安裝，文案刻意不指名；toast 標題用專屬短句，第二行就是上表文案；按鈕保留「重試」，供重新安裝後恢復。只裝 GoFly Mac App、沒有 Xcode 的 Mac 是否也會自動掛載尚未驗證。**2026-11-11 更新（側載版改用 DDI modal，已實作、未實機驗收）**：SideStore 不會掛載 DDI，舊結論「沒有可匿名下載的來源」不再成立——社群 DeveloperDiskImage 鏡像提供檔案，個人化簽署由 Apple TSS 匿名完成（同日以 Mac 內附 pymobiledevice3、不經 Xcode，在 iOS 27.2.1 實機掛載成功）。側載版（`GoFlyRequiresMacSetup=false` 且無正式 activation）遇到此錯誤**不顯示 toast**，改開 Figma 共用元件 `Light · Modal / 裝置支援（DDI）`（DDI.5–6），文案見下方「裝置支援 modal」表；Mac 安裝版維持上表 toast。舊 Figma F11.b 專用 toast 已移除（F11.b 現為設定 › 裝置支援的下載失敗狀態）；設定 › 裝置支援可隨時重新下載（見 IOS-UI-DESIGN.md F11）。

其餘錯誤**不放按鈕**，只留關閉（×）：文案已說明該怎麼做（選起點、選地點、移除一筆再試），使用者直接在原畫面操作即可。

## 2. 文案表

**所有 toast 同一格式：標題＋第二行＋按鈕（可無）**（2026-11-03）。標題用各節的類別標題，第二行就是下表文案，兩者都用短句；通用的「設定 › VPN 通道」修復指引不再當第二行。例外：`error.devicePreparationRequired` 標題「需要啟用裝置支援／Device support needs activation」；`wander.error.planningFailed` 標題「無法規劃路線」、第二行「請在地圖選點或重試。」；座標輸入錯誤（`search.coordinateFormat`、`search.latitudeRange`、`search.longitudeRange`）標題「座標無效／Invalid coordinates」。不在下表的 toast 各有 `<key>.title`：無法開啟系統設定、無法開啟 App Store、無法匯入配對檔、已儲存（最愛路線未含目前位置）、貼上搜尋（無效經緯度、找不到位置、搜尋失敗）。實作在 `IssueCatalog.titleKey(for:)`；尚未在真機驗證。範圍欄：**A**＝App 級（全域），**P**＝頁面／資料級，**M**＝模式級。

### 連線與裝置服務（A，類別標題：裝置連線問題／Device connection issue）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `error.pairingRequired` | 缺少配對資料。請連接 Mac App 完成裝置準備。 | Pairing data is missing. Connect to the Mac app to prepare. | 設定／Settings |
| `error.identityMismatch` | 配對資料屬於其他裝置。請在 Mac App 修復。 | Pairing is for another device. Repair it in the Mac app. | 設定／Settings |
| `error.developerModeRequired` | 請開啟開發者模式，再連接 Mac App 完成準備。 | Turn on Developer Mode, then finish setup in the Mac app. | 設定／Settings |
| `error.devicePreparationRequired` | 請用 USB 連接 Mac，打開 Mac App 重新安裝。（標題：需要啟用裝置支援） | Connect your iPhone to your Mac with USB and reinstall using your Mac app. (Title: Device support needs activation) | 重試／Retry |
| `error.serviceUnavailable` | 無法連接裝置服務。請檢查 VPN 通道。 | Can't reach the device service. Check the VPN tunnel. | 重試／Retry |
| `error.tunnelUnavailable` | 無法連接 VPN 通道。請重新連接 LocalDevVPN 後再試。 | Can't reach the VPN tunnel. Reconnect LocalDevVPN, then try again. | 重試／Retry |
| `error.operationTimedOut` | 裝置未在時限內確認，請重試。 | The device didn't confirm in time. Try again. | 重試／Retry |
| `error.deviceRequired` | 需要已準備的實體 iPhone，模擬器無法執行。 | Needs a prepared iPhone. The Simulator can't run this. | — |
| `error.storageUnavailable` | 無法讀取裝置設定。請檢查儲存空間，並在 Mac App 修復。 | Can't read device settings. Check storage, repair in Mac app. | 設定／Settings |

### 路線規劃與匯入執行（M：路線模式，類別標題：路線無法規劃／Can't plan route）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `route.error.missingStart` | 請選擇起點。 | Choose a start point. | — |
| `route.error.missingDestination` | 請選擇終點。 | Choose a destination. | — |
| `route.error.currentLocationUnavailable` | 目前位置無法確認。請為該節點選擇地點。 | Current location unavailable. Pick a place for that stop. | — |
| `route.error.planningFailed` | 找不到可通行的路徑。請檢查起點，或點選修正。 | No drivable route. Check the start or tap Fix. | 修正／Fix |
| `route.error.invalidPath` | 規劃的路線無效。請重新選擇地點。 | The planned route is invalid. Pick places again. | — |
| `imports.execution.disconnectedSegments` | 各段端點未銜接。僅可預覽或匯出。 | Segments don't connect. Preview or export only. | — |
| `imports.execution.zeroDistance` | 路徑沒有可行進距離。僅可預覽或匯出。 | No travel distance. Preview or export only. | — |

### 搖桿與漫步（M：搖桿模式，類別標題：搖桿無法使用／Joystick unavailable）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `joystick.error.originUnavailable` | 沒有已確認的位置。請設定起點後使用搖桿。 | No confirmed location. Set a start point to use the joystick. | — |
| `joystick.error.noCandidate` | 找不到新的目的地。請在地圖選點或重試。 | No new destination found. Pick one on the map or retry. | 重試／Retry |

### 最愛地點（P，類別標題：最愛地點／Favorite places）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `favorites.error.corruptArchive` | 最愛地點資料已損壞，無法讀取。原有資料已保留。 | Favorites are damaged and can't be read. Data was kept. | — |
| `favorites.error.unsupportedSchema` | 最愛地點資料版本不相容。原有資料已保留。 | Favorites use an unsupported version. Data was kept. | — |
| `favorites.error.unsafeFile` | 無法安全開啟最愛地點。原有資料已保留。 | Can't safely open favorites. Data was kept. | — |
| `favorites.error.unavailable` | 目前無法使用最愛地點，請嘗試重新開啟 GoFly。 | Favorite places are unavailable. Try reopening GoFly. | 重試／Retry |
| `favorites.error.writeFailed` | 變更未能儲存，原有最愛維持不變，請再試一次。 | Couldn't save. Your favorites are unchanged. Try again. | 重試／Retry |
| `favorites.error.invalidPlace` | 無法收藏此地點，請選取有效地點後再試。 | Couldn't save this place. Pick a valid one and retry. | — |
| `favorites.error.invalidLabel` | 標籤請使用 120 個字以內。 | Use 120 characters or fewer for the label. | — |
| `favorites.error.limitExceeded` | 最愛地點已達儲存上限，請移除一筆最愛或縮短標籤後再試。 | Favorites are full. Remove one or shorten the label. | — |
| `favorites.error.notFavorite` | 此地點已不在最愛中，請重新加入後再儲存標籤。 | No longer a favorite. Add it again before labeling. | — |

### 匯入路線清單（P，類別標題：匯入路線／Imported routes）

| 代碼 | 繁體中文 | English | 按鈕 zh／en |
| --- | --- | --- | --- |
| `imports.error.corruptArchive` | 匯入路線清單已損壞，暫時無法變更。 | The imported routes list is damaged and can't be changed for now. | — |
| `imports.error.unsupportedSchema` | 尚未支援此匯入清單版本。 | This imported list version isn't supported yet. | — |
| `imports.error.unsafeFile` | 無法安全讀取保存的路線檔案，請重新匯入來源檔案。 | Can't safely read the saved route. Re-import the file. | 選檔／Choose |
| `imports.error.unavailable` | 暫時無法讀取匯入路線，請再試一次。 | Imported routes can't be read right now. Please try again. | 重試／Retry |
| `imports.error.writeFailed` | 無法儲存變更，原清單已保留。請再試一次。 | Couldn't save. The previous list was kept. Try again. | 重試／Retry |
| `imports.error.limitExceeded` | 匯入清單已達儲存上限，請先移除不需要的路線。 | The import list is full. Remove unused routes first. | — |
| `imports.error.invalidFilename` | 檔名不受支援，請重新命名來源檔案後再試。 | Unsupported file name. Rename the file and retry. | 選檔／Choose |
| `imports.error.notFound` | 此匯入路線已不存在，請選擇其他路線。 | This route is no longer available. Pick another. | — |
| `imports.error.metadataMismatch` | 保存的路線與清單資料不符，請重新匯入來源檔案。 | The saved route doesn't match its list. Re-import the file. | 選檔／Choose |
| `imports.error.hashMismatch` | 保存的路線未通過驗證，請重新匯入來源檔案。 | The saved route failed verification. Re-import the file. | 選檔／Choose |
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
| `favoriteRoutes.error.writeFailed` | 無法儲存變更，原最愛路線已保留。請再試一次。 | Couldn't save. Favorite routes are unchanged. Try again. | 重試／Retry |
| `favoriteRoutes.error.limitExceeded` | 最愛路線已達儲存上限，請先移除不需要的路線。 | Favorite routes are full. Remove unused routes first. | — |
| `favoriteRoutes.error.invalidLabel` | 標籤最多 120 字，且不能包含換行。 | Labels can be up to 120 characters and can't contain line breaks. | — |
| `favoriteRoutes.error.invalidPlace` | 路線地點資料無效，請重新選擇該地點後再儲存。 | A route place is invalid. Re-pick it before saving. | — |
| `favoriteRoutes.error.tooFewValidPlaces` | 至少需要兩個有效地點。請先在地圖或搜尋中選擇地點。 | Needs at least two valid places. Pick places first. | — |
| `favoriteRoutes.error.notFound` | 此最愛路線已不存在。 | This favorite route no longer exists. | — |
| `favoriteRoutes.error.metadataMismatch` | 保存的最愛路線與清單資料不符。 | The saved favorite route doesn't match the list data. | — |
| `favoriteRoutes.error.hashMismatch` | 保存的最愛路線未通過驗證，無法載入。 | The saved favorite route failed verification and can't be loaded. | — |
| `favoriteRoutes.error.noSelection` | 請先選擇最愛路線。 | Select a favorite route first. | — |
| `favoriteRoutes.error.busy` | 請等待目前最愛路線操作完成。 | Wait for the current favorite route operation to finish. | — |
| `favoriteRoutes.error.nothingToUndo` | 目前沒有可復原的刪除路線。 | There's no deleted route to undo. | — |

### GPX 內容（P，類別標題：無法匯入 GPX／Can't import GPX）

13 項按鈕全部為 **選檔／Choose**。

| 代碼 | 繁體中文 | English |
| --- | --- | --- |
| `gpx.error.invalidXML` | GPX 檔案的 XML 格式無效，請選擇其他檔案。 | The GPX file has invalid XML. Choose another file. |
| `gpx.error.unsupportedVersion` | 僅支援 GPX 1.1 格式。 | Only GPX 1.1 is supported. |
| `gpx.error.unsupportedNamespace` | 檔案未使用標準 GPX 1.1 格式。 | The file doesn't use the standard GPX 1.1 format. |
| `gpx.error.unsupportedEncoding` | 請將 GPX 檔案儲存為 UTF-8 或 UTF-16 後再試。 | Save the GPX file as UTF-8 or UTF-16 and try again. |
| `gpx.error.unsafeXML` | 檔案含不支援的 XML 宣告，請選擇標準 GPX 1.1 檔案。 | Unsupported XML. Choose a standard GPX 1.1 file. |
| `gpx.error.invalidPoint` | 檔案含無效座標，整份檔案未匯入。 | Invalid coordinate found. Nothing was imported. |
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
| `recovery.error.unavailable` | 無法存取已存工作階段，請檢查可用儲存空間。 | Can't access the saved session. Check storage. | 重試／Retry |
| `recovery.error.unsafeFile` | 無法安全讀取工作階段檔案，原始資料已保留。 | Can't safely read the session file. It was kept. | — |
| `recovery.error.writeFailed` | 無法儲存變更，請檢查可用空間後重試。 | Couldn't save changes. Check storage and retry. | 重試／Retry |
| `recovery.error.corruptArchive` | 已存工作階段已損壞，原始資料未被取代。 | The saved session is damaged. Data wasn't replaced. | — |
| `recovery.error.unsupportedSchema` | 不支援此工作階段格式，原始資料已保留。 | Unsupported session format. Data was kept. | — |
| `recovery.error.limitExceeded` | 工作階段超過支援的儲存上限，未儲存此次變更。 | The session exceeds storage limits and wasn't saved. | — |
| `recovery.error.invalidSnapshot` | 工作階段資料無效，未儲存此次變更。 | The session data is invalid. This change wasn't saved. | — |
| `recovery.error.revisionExhausted` | 無法繼續儲存此工作階段，原始資料已保留。 | This session can't save changes. Data was kept. | — |

## 3. 處理邏輯（從簡）

1. **能重試就只給「重試」**。重試 = 重設工作階段後重跑原操作，不讓使用者判斷該重置哪一層。連線類（`serviceUnavailable`、`tunnelUnavailable`、`operationTimedOut`）、存取／寫入失敗類（`unavailable`、`writeFailed`）都走這一條。Wi‑Fi 與路線規劃失敗的「重試」只重新檢查／重新規劃，不重置工作階段。
2. **重試失敗不加新 toast**，只更新原 toast；重試中按鈕顯示進行中並停用。連續失敗 2 次後，把按鈕換成「設定」。
3. **無法由 App 修復的**（配對、開發者模式、儲存空間）→「設定」。
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

## 裝置支援 modal（側載版，DDI.1–3、DDI.5–6）

不是 toast；固定高度 modal 的文案。錯誤文字放在預留的 2 行位置。

| Key | 繁中 | English |
| --- | --- | --- |
| `support.modal.title.onboarding`／`.onboardingFailed` | 準備裝置支援／無法準備裝置支援 | Preparing device support／Couldn't prepare device support |
| `support.modal.title.map`／`.mapFailed` | 啟用裝置支援／無法啟用裝置支援 | Activate device support／Couldn't activate device support |
| `support.modal.message.onboarding` | 首次使用需下載裝置支援（約 16 MB），讓 GoFly 能在這支 iPhone 模擬定位。 | First use downloads device support (about 16 MB) so GoFly can simulate location on this iPhone. |
| `support.modal.message.map` | iOS 更新後需要重新啟用裝置支援（約 16 MB）。完成後會自動重試剛才的動作。 | Device support needs to be reactivated after an iOS update (about 16 MB). Your last action retries when it finishes. |
| `support.step.download` | 下載裝置支援（唯一步驟列；下載後的啟用顯示在同列右側「啟用中…」，2026-11-11 移除獨立啟用列） | Download device support |
| `support.step.*` 狀態 | 等待中、下載中…、啟用中…、完成、失敗；下載中顯示「8.2 / 16 MB」 | Waiting, Downloading…, Activating…, Done, Failed |
| 按鈕 | 下載中…／啟用中…（停用）；失敗為「重試」 | Downloading…／Activating… (disabled); Retry on failure |
| `support.download.error.network` | 無法連線到下載伺服器，請檢查網路後重試。 | Couldn't reach the download server. Check your internet connection and try again. |
| `support.download.error.invalid` | 下載的檔案不完整，請稍後再試。 | The downloaded files were incomplete. Try again later. |
| `support.download.error.storage` | 儲存空間不足，請釋放空間後重試。 | Not enough storage to save device support. Free up space and try again. |
| `support.activate.error.connection` | 無法連線到這支 iPhone，請確認 Wi‑Fi 與 LocalDevVPN 已連線後重試。 | Couldn't reach this iPhone. Make sure Wi‑Fi and LocalDevVPN are connected, then try again. |
| `support.activate.error.rejected` | iPhone 未能啟用裝置支援，請稍後重試。 | This iPhone didn't activate device support. Try again in a moment. |
