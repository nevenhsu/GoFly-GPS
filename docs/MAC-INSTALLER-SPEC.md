# GoFly GPS Mac 安裝器規格

正式品牌標題使用 GoFly GPS，App 內一般句子保留 GoFly，README 統一使用 GoFly GPS；詳見 [命名規範](BRANDING.md)。識別碼與技術路徑維持相容。

這份文件定義 GoFly Mac 安裝器的現行規格。視覺以 Figma「05 · Mac Redesign（新版）」（`123-61504`）的「V1」section 渲染畫面為準。DMG 打包流程見 [Mac 開發說明](../app/GoFlyMac/DEVELOPMENT.md)。

## 1. 目標

一般使用者只需要：

1. 下載 GoFly Mac 的 DMG 並開啟。
2. 照 GoFly 的畫面，在**全新的 Mac** 上準備好 macOS、Xcode、iOS 平台，並在 Xcode 登入**自己的** Apple 帳號（免費帳號即可）。
3. 用 USB 連接 iPhone，按一次「安裝 GoFly」。GoFly 用使用者自己的 Team 建置、簽名，並完成配對交接。
4. 之後不需要再插線：Mac App 開著時，簽名剩不到 4 天會自動延長（USB 或同一個 Wi‑Fi）；也可以手動按「延長簽名」。

不提供備份、還原或重置功能；不支援 Intel Mac、付費 Developer ID 公證，也不代替使用者輸入密碼或接受條款。

### 1.1 與 SideStore IPA 的界線

Mac producer 使用來源 `GoFlyRequiresMacSetup=true`，安裝／renew 的 pairing、support 與精確 activation receipt 驗證均保留。SideStore IPA 僅由獨立打包腳本把 Payload 副本旗標改為 `false`，不修改來源或 Mac 內建 iOS project。兩者共用 iOS onboarding；權限授權與 VPN 可達不等於配對或定位就緒。Mac 不提供側載 Bundle ID 的準備能力；Team／Bundle ID 規則不變。驗收需區分 IPA 能啟動、正式 Mac setup 完成與定位成功。

## 2. iOS App 依賴

| iOS App 需要的東西 | 由誰提供 | 使用者要做什麼 |
| --- | --- | --- |
| 用使用者 Team 簽名的 GoFly.app（`com.neven.gofly.<teamid>`） | Mac App 內附 iOS 專案原始碼與預編譯的 `libidevice_ffi.a`，在本機用 `xcodebuild` 建置並自動簽名 | 安裝 Xcode、下載 iOS 平台、登入 Apple 帳號 |
| 開發憑證與描述檔（免費 Team 7 天） | Xcode 自動管理（`-allowProvisioningUpdates`），需要連網 | 第一次簽名時，在鑰匙圈視窗輸入 Mac 登入密碼並點「永遠允許」 |
| 配對資料（GoFly 連 `10.7.0.1` 上的 remotepairingd 用；連接埠每次以 Bonjour `_remotepairing._tcp` 自動探索，不寫死） | 首次安裝時由 Mac 透過 USB 建立並交付 | 在 iPhone 點「信任」並輸入 iPhone 密碼 |
| 裝置支援檔（26.0–26.3 用 personalized DDI，26.4 起用 cryptex） | Mac 依實際 iOS 版本準備並交付；手機不自行下載 | 無 |
| 開發者模式 | iOS 設定 | 開啟開發者模式 → 重新開機 → 點「開啟」 |
| 信任開發者（免費 Team） | iOS 設定 | 設定 › 一般 › VPN 與裝置管理 › 信任 |
| LocalDevVPN | App Store | 在 iPhone 安裝並允許 VPN |
| 啟用回報（activation receipt） | iOS App 開啟時提交，Mac 讀回 | 無；Mac 讀到之前不顯示「完成」 |

不同 Bundle ID 視為不同 App，資料不會自動移轉；換 Team 產生不同 Bundle ID 時亦同。免費 Team 每支手機最多 3 個自簽 App，7 天內新增 App ID 的數量受限。

Python、pymobiledevice3 和 Bridge 都打包在 App 內，**使用者不會看到 Python 步驟**。不另外安裝命令列工具：GoFly 直接用 Xcode.app 內的 `DEVELOPER_DIR`，不依賴 `xcode-select` 的設定。

## 3. 取得與開啟 GoFly Mac（App 外）

DMG 內含 `GoFly.app`、`install.sh` 與 `THIRD-PARTY-NOTICES.md`。建置器在忽略的 `work/dist/` 輸出版本化 arm64 DMG 及相符 `.sha256` sidecar；正式發行時需把同版 DMG 與 checksum 一起發布並在 README 提供核對方式。使用者核對 checksum 後，在「終端機」執行 `bash /Volumes/GoFly/install.sh`。腳本只替換 `/Applications/GoFly.app`，覆蓋前詢問、移除已安裝 App 的隔離屬性再開啟，不使用 sudo、不修改 Gatekeeper，也不移除 GoFly state 或手機資料。App 使用 ad-hoc 深度簽署，沒有 Developer ID 或 notarization。此步驟不設 Figma 畫面。

## 4. Mac 環境（預設是全新的 Mac）

每次開啟 GoFly 都先顯示 **E00 啟動畫面（loading）**：GoFly 圖示、「GoFly for Mac」、進度條與「正在檢查 Mac 環境…」，版面與 iOS 啟動畫面 R01 一致。畫面上不列檢查清單，也不會打勾後停留；背後以唯讀方式檢查（約 1–3 秒；500 ms 內完成就不顯示，避免閃一下）。檢查完直接跳轉：

- **全部通過** → 跳過整個 E 流程，直接進入裝置頁（依手機狀態顯示 D01／D02–D04／D08 等）。
- **有未完成的項目**：
  - 第一次開啟 GoFly、而且 Xcode 未安裝（全新 Mac）→ 先顯示 E01 總覽，按「開始準備」進入第一個未完成的步驟。
  - 其他情況（曾經設定過，或只差幾步）→ **直接跳到第一個未完成的步驟**，順序為 E02 → E03／E04 → E05 → E06 → E07 → E08。
- 每個步驟偵測到完成就自動前往下一個未完成的步驟；最後一步完成後進入裝置頁。
- 檢查本身讀不到結果時才停在 E00，並提供「重新檢查」。
- 檢查結果另外放在 **E09「Mac 環境」**，不在啟動流程中：使用者點裝置頁側欄底部的「Mac 環境已就緒」才打開，可以查看各項結果、重新檢查或更換 Team。

側欄顯示步驟清單（完成＝綠色 ✓，目前＝黑底）。每一步都保留「重新檢查」。Figma 的「Flow · 啟動流程」畫出了這段跳轉。

| 畫面 | 檢查／步驟 | 使用者要做的事 | 會用到的密碼 |
| --- | --- | --- | --- |
| E00 啟動畫面（loading） | 每次開啟時的唯讀檢查 | 等待 | — |
| E01 準備這部 Mac | 第一次開啟且 Xcode 未安裝時的總覽：macOS 版本、可用空間、Xcode、Xcode 元件、iOS 平台、Apple 帳號、開發團隊；預估時間約 1 小時，需要約 40 GB 可用空間 | 點「開始準備」 | — |
| E02 更新 macOS | macOS 版本低於 Xcode 的最低需求時才出現 | 系統設定 › 一般 › 軟體更新 › 立即更新 | Mac 登入密碼 |
| E03 取得 Xcode | 未安裝 Xcode | 開啟 App Store → 尚未登入 App Store 時先登入 → 點「取得」→「安裝」 | Apple 帳號密碼 |
| E04 等待 Xcode 安裝 | 偵測 `/Applications/Xcode.app` 出現 | 等待（約 3 GB 下載、30–60 分鐘）；期間可以先在 iPhone 安裝 LocalDevVPN | — |
| E05 第一次開啟 Xcode | 未同意授權條款或元件未安裝 | 點「開啟 Xcode」→ 授權條款點「同意」→ 輸入 Mac 登入密碼 → 等元件安裝完 | Mac 登入密碼 |
| E06 下載 iOS 平台 | 沒有 iOS 平台 | Xcode 平台視窗勾選 iOS → 點「下載並安裝」（約 8 GB）；或 Xcode › Settings › Components。 | — |
| E07 在 Xcode 登入 Apple 帳號 | Xcode 沒有 Apple 帳號 | Xcode › Settings › Apple Accounts › + › Apple Account → 登入、雙重認證；沒有帳號時提供「免費建立 Apple 帳號」連結 | Apple 帳號密碼、雙重認證碼 |
| E08 選擇開發團隊 | 有多個 Team 時才出現；只有 1 個時自動選取 | 選一個，各項標示「個人（免費・7 天）」或「團隊」 | — |
| E09 Mac 環境（檢查結果） | 從側欄底部打開，不在啟動流程中 | 查看結果、重新檢查、更換 Team | — |

唯讀 `environment` 依序回報 macOS 版本、可用空間、Xcode 安裝、Xcode 初次啟動／授權、iOS 平台及 Apple 帳號六項檢查，另回報 Team 清單。檢查狀態為通過、未通過或未知；無法讀取時不得當成通過。E01 是否第一次開啟以本機偏好旗標判斷。macOS 最低版本取已安裝 Xcode 的 `LSMinimumSystemVersion`；尚未安裝時依目前規劃的 Xcode 27.1（最低 macOS 26.6）判斷。可用空間以 `/Applications` 所在磁碟為準，至少 40 GB。只讀檢查不執行 `-runFirstLaunch`、不接受授權、不下載平台。若 GoFly 內建資源驗證失敗，只顯示「GoFly 無法啟動，請重新安裝」。

Bridge、Python 與 iOS 專案都打包在 DMG 內，沒有「App 資源」或「Python 環境」的設定步驟。萬一 App 內建檔案被修改或刪除，只顯示通用錯誤視窗「GoFly 無法啟動，請重新安裝」，不另外設計畫面。

GoFly 只打開 App Store、Xcode、系統設定和網頁，不代替使用者點擊、接受條款或輸入密碼。文案必須說清楚要輸入哪一種密碼：Mac 登入密碼、iPhone 密碼或 Apple 帳號密碼。

### Mac 色彩系統

- Mac App 的色彩 token 集中在 `app/GoFlyMac/Sources/GoFlyMac/MacColorSystem.swift`，以語意角色提供畫布、側欄、卡片、文字、分隔線、互動、狀態與品牌色，依 macOS 淺／深外觀解析。
- 所有 Mac 畫面都使用這套 Mac 專屬 token；View 不直接指定 hex、RGB 或 `Color.black`／`Color.green` 等原始色值。新增顏色或更換 Mac theme 時只改這套 palette，逐頁檢查外觀。
- 色值依 Figma「05 · Mac Redesign（新版）」V1 淺／深色渲染稿；不從 `app/GoFly` 匯入色彩程式或 token。iOS App 與 Mac App 各自維護平台色彩系統。
- V1 不新增 theme 選擇器；色彩跟隨系統外觀。驗收需檢查淺／深色畫面，並確認 Mac 色彩修改不改變 iOS 色彩。

## 5. 裝置（日常唯一的畫面）

**簽署有效期**：剩餘天數取自描述檔到期日（以安裝時間點簽出）。免費 Personal Team 為 7 天，到期後須重新安裝；付費開發者帳號依其描述檔（約 1 年）顯示，不壓成 7 天。Mac 與 iOS 顯示同一個值。免費或付費以 Xcode 帳號記錄的 `isFreeProvisioningTeam` 判斷，不以描述檔有效期間長短判斷：免費 Team 的到期日 = 簽名時間（`codesign` 的 Signed Time，讀不到時用描述檔建立時間）+ 7 天，且不晚於描述檔到期日；付費或無法判斷時用描述檔到期日。setup producer 檢查 App 時就套用這條規則，所以交給 iPhone 的啟用收據、Mac 顯示與自動延長簽名都用同一個日期。

App 以**裝置為中心**。側欄列出看得到的 iPhone（USB／Wi‑Fi 標章、剩餘天數）和「↻ 重新搜尋」。裝置名稱用手機「設定 › 一般 › 關於本機 › 名稱」：掃描時透過既有 USB 配對讀取（不配對、不跳信任），檢查手機後依手機記住；讀不到（未信任）才顯示「iPhone · …末六碼」。底部顯示 Mac 環境狀態（例：「Mac 環境已就緒 · Neven（個人）」，點了可以看檢查結果或換 Team）。右側顯示選取那支手機的狀態，**同一時間只有一個主要按鈕**：

| 手機狀態 | 連線 | 主要按鈕 | 畫面 |
| --- | --- | --- | --- |
| 沒有手機 | — | 無 | D01 |
| 未信任／未開開發者模式 | USB | 無；準備清單 | D02、D03 |
| 已準備、沒有 GoFly | USB | **安裝 GoFly** | D04 |
| 沒有 GoFly | Wi‑Fi | 停用：「第一次安裝需要 USB 連接」 | D12 |
| 已安裝 GoFly | USB 或 Wi‑Fi | **延長簽名**；Mac 上有新版時改為「更新並延長簽名」 | D08、D09 |
| 簽名已過期 | USB 或 Wi‑Fi | **延長簽名**；說明「過期只是暫時無法開啟，資料還在」 | D08 的狀態 |
| 選取的 Wi‑Fi 手機找不到 | Wi‑Fi | 無；列出 Wi‑Fi 條件與「改用 USB」 | D13 |

### 5.1 首次安裝（只限 USB）

1. **準備清單**（D02–D04，同一頁）：USB 已連接 → 已信任這部 Mac → 開發者模式已開啟。卡住的那一項顯示 iPhone 畫面示意圖與「點這裡」。全部打勾後出現「安裝 GoFly」，按下就開始；**沒有另外的確認頁**，裝置名稱、iOS 版本與 Team 在同一頁顯示。安裝前的唯讀檢查（preflight）通過後直接進入安裝，不再要求第二次按「安裝」；「重新開始」相同。Mac App 的安裝、延長簽名、重新開始與重試一律帶 `allowProvisioningUpdates: true`，讓 Xcode 更新描述檔；USB 時另以 `-destination platform=iOS,id=<UDID>` 指名這支手機並加 `-allowProvisioningDeviceRegistration`，Xcode 才會把新手機登記到所選 Team（單靠 `-allowProvisioningUpdates` 不會登記）；Apple 回報 Team 登記的 iPhone 已達上限時，建置以 `device-limit-reached` 停在建置階段並說明要改用已登記的手機或先移除一支，不歸為一般失敗；同一頁列出佔用名額的手機（唯讀 `registeredDevices`：取自這部 Mac 上該 Team 的 Xcode 描述檔，名稱來自 Xcode 裝置清單或 GoFly 記住的名稱，未知時顯示「名稱不明」與末六碼）。GoFly 不提供刪除：免費 Team 沒有 Apple 的裝置管理頁或 API，私有 Apple 服務需要 GoFly 接手 Apple ID 登入，違反本規格；空出名額後按「重新開始」；描述檔不含這支手機時建置會以 `identity-mismatch` 停在建置階段。
2. **安裝中**（D05）：建置 GoFly → 簽名 → 安裝到 iPhone → 交付配對 → 準備裝置支援。第一次簽名跳出鑰匙圈視窗時，在同一頁顯示示意圖（Mac 登入密碼、點「永遠允許」）。
3. **在 iPhone 完成設定**（D06）：信任開發者（免費 Team）→ 安裝 LocalDevVPN → 開啟 GoFly。Mac 讀到啟用回報後才前進。
4. **完成**（D07）：顯示實際讀回的到期日，以及「Mac App 開著時會自動延長簽名」。

### 5.2 延長簽名（USB 或 Wi‑Fi）

- 流程：建置 → 簽名 → 覆蓋安裝（保留資料）→ 核對配對與裝置支援 → 讀回啟用回報 → 完成（D11：新的到期日、「手機上的資料和設定已保留」）。
- 手動：在 D08／D09 按主要按鈕就開始，不另設確認頁。版本不同時，按鈕上方寫明「build 21 → build 24，資料保留」。
- **Wi‑Fi 時只核對手機上現有的配對**，不重新建立；核對失敗時要求接 USB。USB 時照首次安裝的規則重新交付配對。
- Wi‑Fi 條件：Mac 與 iPhone 在同一個網路、iPhone 之前用 USB 配對過這部 Mac、iPhone 已解鎖。

### 5.3 自動延長簽名

- 時機：Mac App 開著時，啟動時檢查一次，之後每 24 小時檢查一次。
- 條件：已安裝 GoFly、**簽名剩不到 4 天**（含已過期）、手機可以用 USB 或 Wi‑Fi 連上（兩者都有時用 USB）、Mac 能連網、目前沒有其他操作進行中。
- 裝置頁有「自動延長簽名」開關，預設開啟。
- 執行中顯示 D10「正在自動延長簽名」，並發出 macOS 通知。畫面上的警告：**不要拔掉 USB、不要關閉 Wi‑Fi、不要讓 Mac 睡眠或關閉 GoFly**。執行期間 GoFly 會讓 Mac 保持喚醒。使用者可以按「取消」。
- 失敗或找不到手機時顯示 D14／D13，不立刻自動重試；下一次 24 小時檢查時從頭再試。使用者隨時可以按「重新開始」或「延長簽名」。剩不到 4 天才觸發，所以到期前至少有三次自動檢查。

### 5.4 中斷與失敗

- 安裝或延長簽名中斷、失敗（USB 拔掉、Wi‑Fi 斷線、Mac 睡眠、App 被關閉）時顯示 D14。唯一的動作是「**重新開始**」，會從頭重新安裝或重新簽名，**不做接續**。
- 重新開始前，先重新觀察手機狀態。手機上已經有 GoFly 就用覆蓋安裝（保留資料）；USB 時重新產生配對，並先作廢舊的、還沒用掉的配對，不套用舊交易的配對。
- Setup producer 以一筆全域現行 journal 序列化交易。`apply` 遇到任何裝置留下的未完成 journal 時，會先在原交易資料夾中耐久封存為 `journal.abandoned.json`，再移除現行指標並建立新交易；不刪除 App、配對檔或原交易資料夾。只有已證明完成的交易可封存為 `journal.completed.json`；同一 setupID 重送仍衝突。iOS 消費者在讀取前原子 rename `incoming.plist` 為 `incoming.plist.consuming`；Mac 作廢舊交接時原子 rename 到以舊交易 ID 標記的隔離路徑，再驗證並只刪除該隔離檔。若 iOS 已認領、出現替換檔或狀態不明，producer fail closed，不封存舊交易或刪除使用者資料。
- 手機上遺留的握手控制檔（`readback-request.json`、`readback-response.json`、`incoming.json`）：「重新開始」時自動處理，不需使用者操作。完整且屬於現行啟用收據的一組封存到 `retired/<setupID>-<nonce>`；不完整（中斷）、不屬於現行收據、或封存名稱已被先前嘗試佔用的，**移入 `retired/abandoned-<uuid>` 後以全新握手檔繼續**，只搬移、不刪除，啟用收據、配對檔、支援映像與使用者資料不動；沒有控制檔時直接繼續。待消費的配對信封（`incoming.plist`）或任何 `.staging` 檔仍須 fail closed。
- 重新開 Mac App 時，如果上次有未完成的操作，同樣顯示 D14，不提供「繼續」。
- 安裝、延長簽名或「重新開始」進行中，以及 D14 時，操作中的那支手機一律留在側欄，即使這次還沒掃描到它。
- D14 側欄狀態依操作類型：首次安裝顯示「安裝未完成」，延長簽名顯示「延長簽名未完成」。
- 未完成的操作只鎖住它自己那支手機。D14 時「重新搜尋」仍會更新清單；若原手機已拔掉、改接另一支 USB 手機，就自動選取新手機並從頭檢查（右側回到 D02–D04，不停在「重新開始」）；也可以直接點側欄的另一支手機。原交易的 journal 不在 Mac App 端改動，由下一次 `apply` 依上列規則封存為 `journal.abandoned.json`；若在那之前重開 Mac App，仍顯示原手機的 D14。

## 6. 畫面清單（Figma V1）

以下畫面各有淺色與深色版本，另附啟動流程圖：

| 編號 | 畫面 |
| --- | --- |
| E00 | 啟動畫面（loading，每次開啟） |
| E01 | 準備這部 Mac（總覽，只在全新 Mac 第一次開啟時） |
| E02 | 更新 macOS |
| E03 | 取得 Xcode（App Store） |
| E04 | 等待 Xcode 安裝 |
| E05 | 第一次開啟 Xcode（同意條款） |
| E06 | 下載 iOS 平台 |
| E07 | 在 Xcode 登入 Apple 帳號 |
| E08 | 選擇開發團隊 |
| E09 | Mac 環境（檢查結果，從側欄打開） |
| D01 | 尚未連接 iPhone |
| D02 | 準備 iPhone：信任這部 Mac |
| D03 | 準備 iPhone：開啟開發者模式 |
| D04 | 可以安裝 |
| D05 | 正在安裝（鑰匙圈提示） |
| D06 | 在 iPhone 完成設定 |
| D07 | 安裝完成 |
| D08 | 已安裝：延長簽名 |
| D09 | 有新版：更新並延長簽名 |
| D10 | 正在自動延長簽名 |
| D11 | 延長簽名完成 |
| D12 | 需要 USB 連接 |
| D13 | 找不到這支 iPhone（Wi‑Fi） |
| D14 | 未完成：重新開始 |

## 7. 驗收條件

- 每次開啟都先顯示 E00 啟動畫面（或 500 ms 內完成而略過），畫面上不出現檢查清單或打勾。全部通過時直接進入裝置頁；有未完成時直接跳到第一個未完成的步驟，只有全新 Mac 第一次開啟時才先顯示 E01。
- 全新 Mac：照畫面能完成所有步驟；每一步都能自動偵測完成，不需要手動重新啟動 GoFly。
- 環境已就緒的 Mac：開啟後直接看到裝置頁。只有 1 個 Team 時不出現 E08。全程沒有 Python 或命令列工具步驟。
- 首次安裝從插上 USB 到開始安裝，使用者在 Mac 上只按一個按鈕。
- 已安裝 GoFly 的手機只有一個主要按鈕；Wi‑Fi 連接時可以延長簽名。
- 自動延長簽名：啟動時與每 24 小時檢查；剩不到 4 天且手機連得到時，會自動開始並顯示 D10；剩 4 天以上不觸發；失敗後等下一次檢查才再試。
- 只有讀回啟用回報後才顯示「完成」與新的到期日；讀不到時寫「待確認」。
- 中斷後只能「重新開始」；重新開始不會套用舊交易的配對，覆蓋安裝保留資料。
- 1000 × 700 pt 下內容可捲動、底部按鈕可按到；深淺色都清楚可讀。
- Mac 所有色彩都來自 Mac 專屬語意 token；淺／深色符合 Figma，檢視畫面程式時沒有散落的原始色值，iOS 色彩程式不受影響。
