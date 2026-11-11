# GoFly iOS 共用 Status Pill 錯誤清單

2026-10-24。以正式錯誤來源與繁體中文資源核對，共 77 個不重複項目。這是可由來源回報的目錄，不代表每項都正在發生，也不代表新增對應故障測試。

五態只有：啟動／Standby（灰）、模擬中／Running（綠）、暫停／Paused（黃）、停止／Stopped（灰）、錯誤／Error（紅）。任何下列共用狀態錯誤存在時優先顯示 Error，具體原因保留各自文案；不再有 limited。

模擬中與暫停只由「目前的移動」（`ActiveMovement`）判斷：執行中或漫步等下一段目的地為模擬中；暫停、連線中斷待修復與結果未知為暫停。2026-11-01 起，漫步因離開前景、背景執行失效或連線中斷而停下（suspended）也算暫停，與地圖的「漫步暫停」提示一致；先前 pill 在這種情況不顯示暫停。暫停原因（使用者、連線、背景）只決定是否另外顯示提示：使用者自己按暫停的路線或漫步不再跳提示。程式已改，實機待驗。2026-11-02 修正：暫停提示（路線／漫步／瞬移位置的繼續 Toast）按 × 後即隱藏，底部繼續面板仍提供「繼續」；移動再次進入可繼續狀態或背景通知內容改變時重新顯示。實機回報：漫步因 iOS 收回背景任務（`background.taskExpired`）暫停後，舊版 × 無法關閉提示；修正已通過 `swift test` 與建置，實機待驗。

D8 的 `route.error.planningFailed` 依 Figma 04 渲染由路線頁浮動 danger toast 顯示；共用 StatusPill 維持「啟動」，不把單純道路規劃失敗提升為 session Error。

| 類別 | 項目數 | 觸發來源 |
| --- | --- | --- |
| 連線與裝置服務 | 9 | 探測 unavailable/timedOut、ServiceController.error；route/joystick 包裝同一裝置錯誤不重複計數 |
| 路線規劃與匯入執行 | 7 | RouteExecutionController.error，含匯入路線執行失敗 |
| 搖桿與漫步 | 2 | JoystickMovementController.error 或 wanderError |
| 最愛地點 | 9 | FavoritePlacesStore.error／blocked |
| 匯入路線清單 | 13 | ImportedRoutesStore.error／blocked |
| 最愛路線清單 | 15 | FavoriteRoutesStore.error／blocked |
| GPX 內容（透過路線清單錯誤呈現） | 13 | 清單操作回報的 GPXFailure |
| Session 復原資料 | 8 | SessionRecoveryStore.error／blocked |

## 連線與裝置服務

| 代碼 | 繁體中文文案 |
| --- | --- |
| `error.pairingRequired` | 缺少配對資料。請連接 Mac App 完成裝置準備。 |
| `error.identityMismatch` | 配對資料屬於其他裝置。請在 Mac App 修復。 |
| `error.developerModeRequired` | 請開啟開發者模式，再連接 Mac App 完成準備。 |
| `error.devicePreparationRequired` | Mac 安裝版：請用 USB 連接 Mac，打開 Mac App 重新安裝。側載版：不顯示 toast，改開裝置支援（DDI）modal 下載並啟用（見 IOS-ERROR-TOAST-COPY.md）。（toast 標題：需要啟用裝置支援） |
| `error.serviceUnavailable` | 無法連接裝置服務。請檢查 VPN 通道。 |
| `error.tunnelUnavailable` | 無法連接 VPN 通道。請重新連接 LocalDevVPN 後再試。 |
| `error.operationTimedOut` | 裝置未在時限內確認，請重試。 |
| `error.deviceRequired` | 需要已準備的實體 iPhone，模擬器無法執行。 |
| `error.storageUnavailable` | 無法讀取裝置設定。請檢查儲存空間，並在 Mac App 修復。 |

## 路線規劃與匯入執行

| 代碼 | 繁體中文文案 |
| --- | --- |
| `route.error.missingStart` | 請選擇起點。 |
| `route.error.missingDestination` | 請選擇終點。 |
| `route.error.currentLocationUnavailable` | 目前位置無法確認。請為該節點選擇地點。 |
| `route.error.planningFailed` | 找不到可通行的路徑。請檢查起點，或點選修正。 |
| `route.error.invalidPath` | 規劃的路線無效。請重新選擇地點。 |
| `imports.execution.disconnectedSegments` | 各段端點未銜接。僅可預覽或匯出。 |
| `imports.execution.zeroDistance` | 路徑沒有可行進距離。僅可預覽或匯出。 |

## 搖桿與漫步

| 代碼 | 繁體中文文案 |
| --- | --- |
| `joystick.error.originUnavailable` | 沒有已確認的位置。請設定起點後使用搖桿。 |
| `joystick.error.noCandidate` | 找不到新的目的地。請在地圖選點或重試。 |

搖桿／漫步起點（2026-10-26 修正）：依序採用已驗證的模擬位置、裝置仍保持的模擬位置（箭頭變灰、未經 Stop／Restore 清除），最後才是 15 秒內的真實 GPS。只有三者皆無時才顯示 `joystick.error.originUnavailable`；背景往返、保持位置暫停或單次未送出都不會使起點失效，第一個 ACK 會重新驗證箭頭。

## 最愛地點

| 代碼 | 繁體中文文案 |
| --- | --- |
| `favorites.error.corruptArchive` | 最愛地點資料已損壞，無法讀取。原有資料已保留。 |
| `favorites.error.unsupportedSchema` | 最愛地點資料版本不相容。原有資料已保留。 |
| `favorites.error.unsafeFile` | 無法安全開啟最愛地點。原有資料已保留。 |
| `favorites.error.unavailable` | 目前無法使用最愛地點，請嘗試重新開啟 GoFly。 |
| `favorites.error.writeFailed` | 變更未能儲存，原有最愛維持不變，請再試一次。 |
| `favorites.error.invalidPlace` | 無法收藏此地點，請選取有效地點後再試。 |
| `favorites.error.invalidLabel` | 標籤請使用 120 個字以內。 |
| `favorites.error.limitExceeded` | 最愛地點已達儲存上限，請移除一筆最愛或縮短標籤後再試。 |
| `favorites.error.notFavorite` | 此地點已不在最愛中，請重新加入後再儲存標籤。 |

## 匯入路線清單

| 代碼 | 繁體中文文案 |
| --- | --- |
| `imports.error.corruptArchive` | 匯入路線清單已損壞，暫時無法變更。 |
| `imports.error.unsupportedSchema` | 尚未支援此匯入清單版本。 |
| `imports.error.unsafeFile` | 無法安全讀取保存的路線檔案，請重新匯入來源檔案。 |
| `imports.error.unavailable` | 暫時無法讀取匯入路線，請再試一次。 |
| `imports.error.writeFailed` | 無法儲存變更，原清單已保留。請再試一次。 |
| `imports.error.limitExceeded` | 匯入清單已達儲存上限，請先移除不需要的路線。 |
| `imports.error.invalidFilename` | 檔名不受支援，請重新命名來源檔案後再試。 |
| `imports.error.notFound` | 此匯入路線已不存在，請選擇其他路線。 |
| `imports.error.metadataMismatch` | 保存的路線與清單資料不符，請重新匯入來源檔案。 |
| `imports.error.hashMismatch` | 保存的路線未通過驗證，請重新匯入來源檔案。 |
| `imports.error.noSelection` | 請先選擇已匯入路線。 |
| `imports.error.busy` | 請等待目前檔案操作完成。 |
| `imports.error.nothingToUndo` | 目前沒有可復原的刪除路線。 |

## 最愛路線清單

| 代碼 | 繁體中文文案 |
| --- | --- |
| `favoriteRoutes.error.corruptArchive` | 最愛路線清單已損壞，暫時無法變更。 |
| `favoriteRoutes.error.unsupportedSchema` | 尚未支援此最愛路線清單版本。 |
| `favoriteRoutes.error.unsafeFile` | 無法安全讀取保存的最愛路線檔案。 |
| `favoriteRoutes.error.unavailable` | 暫時無法讀取最愛路線，請再試一次。 |
| `favoriteRoutes.error.writeFailed` | 無法儲存變更，原最愛路線已保留。請再試一次。 |
| `favoriteRoutes.error.limitExceeded` | 最愛路線已達儲存上限，請先移除不需要的路線。 |
| `favoriteRoutes.error.invalidLabel` | 標籤最多 120 字，且不能包含換行。 |
| `favoriteRoutes.error.invalidPlace` | 路線地點資料無效，請重新選擇該地點後再儲存。 |
| `favoriteRoutes.error.tooFewValidPlaces` | 至少需要兩個有效地點。請先在地圖或搜尋中選擇地點。 |
| `favoriteRoutes.error.notFound` | 此最愛路線已不存在。 |
| `favoriteRoutes.error.metadataMismatch` | 保存的最愛路線與清單資料不符。 |
| `favoriteRoutes.error.hashMismatch` | 保存的最愛路線未通過驗證，無法載入。 |
| `favoriteRoutes.error.noSelection` | 請先選擇最愛路線。 |
| `favoriteRoutes.error.busy` | 請等待目前最愛路線操作完成。 |
| `favoriteRoutes.error.nothingToUndo` | 目前沒有可復原的刪除路線。 |

## GPX 內容（透過路線清單錯誤呈現）

| 代碼 | 繁體中文文案 |
| --- | --- |
| `gpx.error.invalidXML` | GPX 檔案的 XML 格式無效，請選擇其他檔案。 |
| `gpx.error.unsupportedVersion` | 僅支援 GPX 1.1 格式。 |
| `gpx.error.unsupportedNamespace` | 檔案未使用標準 GPX 1.1 格式。 |
| `gpx.error.unsupportedEncoding` | 請將 GPX 檔案儲存為 UTF-8 或 UTF-16 後再試。 |
| `gpx.error.unsafeXML` | 檔案含不支援的 XML 宣告，請選擇標準 GPX 1.1 檔案。 |
| `gpx.error.invalidPoint` | 檔案含無效座標，整份檔案未匯入。 |
| `gpx.error.invalidParent` | GPX 點位未放在支援的群組中。 |
| `gpx.error.mixedKinds` | 請將軌跡、路線或航點分別存為獨立 GPX 檔案後匯入。 |
| `gpx.error.emptyGroup` | GPX 檔案含空白軌跡、區段或路線。 |
| `gpx.error.tooFewPoints` | GPX 檔案至少需要 2 個有效點。 |
| `gpx.error.pointLimitExceeded` | GPX 檔案超過 10,000 點上限。 |
| `gpx.error.sizeLimitExceeded` | GPX 檔案超過 2 MiB 上限。 |
| `gpx.error.resourceLimitExceeded` | GPX 檔案超過支援的結構上限。 |

## Session 復原資料

| 代碼 | 繁體中文文案 |
| --- | --- |
| `recovery.error.unavailable` | 無法存取已存工作階段，請檢查可用儲存空間。 |
| `recovery.error.unsafeFile` | 無法安全讀取工作階段檔案，原始資料已保留。 |
| `recovery.error.writeFailed` | 無法儲存變更，請檢查可用空間後重試。 |
| `recovery.error.corruptArchive` | 已存工作階段已損壞，原始資料未被取代。 |
| `recovery.error.unsupportedSchema` | 不支援此工作階段格式，原始資料已保留。 |
| `recovery.error.limitExceeded` | 工作階段超過支援的儲存上限，未儲存此次變更。 |
| `recovery.error.invalidSnapshot` | 工作階段資料無效，未儲存此次變更。 |
| `recovery.error.revisionExhausted` | 無法繼續儲存此工作階段，原始資料已保留。 |

## 判斷與清除

- 輸入驗證類（`route.error.missingStart／missingDestination／currentLocationUnavailable`，以及各清單的 `invalidLabel／noSelection／busy／nothingToUndo`）由使用者原地處理，不計入 Error、不讓 Pill 變紅；分類見 `IssueCatalog`，文案與按鈕見 [IOS-ERROR-TOAST-COPY.md](IOS-ERROR-TOAST-COPY.md)。
- 連線恢復、修復成功或正常操作清除實際錯誤後，再依任務狀態顯示 Standby／Running／Paused／Stopped；不是只換文字或關掉 toast。
- 資料仍處於 blocked 時，單獨關閉錯誤提示不讓紅色錯誤態假消失。
- `operationCancelled` 是正常取消，不列為 Error；首次未知、健康探測 pending、定位 ACK pending、使用者暫停／停止也不是錯誤。
- 搜尋框的座標格式／範圍驗證及尚未提交的局部編輯提示維持在原欄位，未納入全域 session pill；啟動交接鎖定頁與 onboarding 也不屬於已進入正常 runtime 的 session pill。
- 連線斷開是 Error 的其中一個原因；配對／資料／規劃錯誤不會因此被誤判為斷線或觸發 reset tunnel。只有運行中真正的可修復連線／服務故障沿既有共用修復入口處理。

## Toast 與 Banner 的呈現

- Toast／Banner 使用共用 overlay 容器，疊在導覽列或搜尋列下方、左右留 16 pt，不參與內容版面；多個通知以 8 pt 間距堆疊，並各自提供關閉按鈕。Toast 浮層陰影依 Figma 04：黑色 18%、y=4 pt、blur=16 pt。
- 狀態語意與既有 `IssueCatalog`、恢復規則及操作語意不變。R04 連線失敗、地圖通知、設定首頁與設定子頁通知、搜尋輸入警告均使用懸浮層；VPN 檢查成功後自動再次確認並進入 B1，不顯示 success Toast。操作表單內的欄位驗證仍留在相關欄位或面板。
- 此處描述 Figma／App 軟體呈現規則，不代表完成實機驗證。
