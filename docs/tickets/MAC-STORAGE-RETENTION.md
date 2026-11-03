# GoFly Mac 安裝資料保留策略 Tickets

狀態：**RET-1、RET-3、RET-6、RET-4 已實作並完成程式審查**（2026-11-03）；RET-2、RET-5 未實作。暫存目錄 Python 測試組 75 項：73 通過、2 項因缺少裝置依賴而跳過。1.0.8（iOS／Mac build 1）的 IPA／DMG 已完成打包與產物完整性校驗；未執行實際安裝或裝置驗證。

實作裁決：依本次明確要求，現行 Wi-Fi 配對來源、每個 deviceID 最新 completed 交易均整筆保留；隔離交接檔與交易根目錄未符合已知命名的 `.staging` 保護整筆，優先於 ≤2 筆目標；已封存交易中 Mac 本機的支援映像暫存（`.support[.actual].<hex>.staging` 與產物目錄內的所有 `.staging`）照 RET-1 回收；其他目錄內的巢狀 `.staging` 不會單憑名稱阻擋產物清理，但未列名的頂層內容仍阻擋整筆回收。此 `.staging` 策略已於 2026-11-03 經使用者確認。建置失敗的 `xcodebuild-error.txt` 列入小型白名單，可隨 RET-6 整筆回收；重複的略過紀錄同一交易只記一次（審查後修正，2026-11-03）。RET-1／RET-3 的配對與 journal 全保留只適用大型產物回收階段，RET-6 隨後可回收符合條件的整筆交易。年齡依封存 journal 的 mtime；建立時間無 birthtime 時記 null。續刪意圖另耐久存於 `state/retention-pending.json`，不依賴會輪替的摘要 log。

## 背景

Mac setup producer 每次安裝或延長簽名都會建立 `~/Library/Application Support/GoFly/state/transactions/<setupID>/`，
裡面的大型產物永遠不會回收。這台 Mac 的 Application Support 曾累積到 20GB 以上。
每筆交易的內容：

| 路徑 | 內容 | 大小 | 可重建 |
| --- | --- | --- | --- |
| `build/` | xcodebuild 輸出的 `GoFly.app` | 大 | 是 |
| `artifact/GoFly.app` | 安裝前驗證快照 | 大 | 是 |
| `support/`（cryptex 另有 `support.actual`） | 裝置支援映像（DDI） | 大，cryptex 存兩份 | 是（重新取得） |
| `pairing.candidate` | USB 配對檔 | 小 | **否** |
| `journal.completed.json`／`journal.abandoned.json` | 封存的交易紀錄 | 小，但數量無上限 | **否** |

共用的 `GoFly/build/project`、`GoFly/build/derived` 每次建置都會先刪再重建，
所以只佔一份空間，不會累積；它的問題是無法增量編譯，影響的是速度（見 RET-5）。

## 不可破壞的約束（所有 ticket 共用）

- **現行交易不動。** `journal.json` 指向的交易，`_completed_eligible` 要求
  `artifact/GoFly.app` 必須存在（`setup_journal.py` `_completed_eligible`）。
  清理只能動**已封存**的交易。
- **被引用的 `pairing.candidate` 一律保留。** Wi‑Fi 延長簽名會沿用來源交易的配對：
  `transactions/<pairingSourceSetupID>/pairing.candidate`（`setup_producer.py` `_wifi_pairing_source`）。
  這個來源可能是好幾次 renew 之前的舊交易。RET-1 到 RET-3 不刪任何配對檔；
  只有 RET-6 會依引用關係刪除整筆舊交易。
- **啟用收據、已安裝的 App、使用者資料都不刪、不搬**（`MAC-INSTALLER-SPEC.md` §5.4）。
  journal 歷史原本也是「不刪、不搬」（AGENTS.md iOS 實機測試安裝節），RET-6 改為有上限的保留，
  實作時須同步改寫該規則（見 RET-4）。
- 清理必須在持有 `operation.lock` 時進行，而且失敗時不能讓安裝結果變成失敗。
- 只刪清單裡列名的子路徑，路徑若是 symlink 或非預期類型就略過並記錄，不做遞迴猜測。

---

## RET-1 封存交易的大型產物回收

**目標**：已封存交易只留下小型證據，大型可重建產物刪除。

**規則**
- 保留完整內容：現行交易，以及**最近一筆** `journal.completed.json` 的交易。
- 其他已封存交易（completed 或 abandoned）：刪除 `build/`、`artifact/`、`support/`、`support.actual`，
  以及殘留的 `.staging` 目錄。
- 保留：`pairing.candidate`、`journal.*.json`、隔離中的交接檔和其他非上列項目。
- 回收後在交易資料夾寫一個 `pruned.json`（時間、刪除的路徑），作為紀錄。

**時機**：新交易 `complete=true` 並封存上一筆之後，同一把 `operation.lock` 內執行。
不另開排程。

**驗收條件**
- 連續安裝或續簽 N 次後，`transactions/` 裡只有 ≤2 筆交易含有 `build/`、`artifact/` 或 `support/`。
- 所有交易的 `pairing.candidate` 和 `journal.*.json` 都還在，內容 SHA-256 不變。
- 清理後立刻做 Wi‑Fi 延長簽名（來源配對在更舊的交易中）仍然成功。
- 清理途中模擬失敗（權限、I/O 錯誤），本次安裝依然回報成功，下次清理會再嘗試。
- symlink 或非目錄的目標不會被刪，並寫入紀錄。

## RET-2 裝置支援映像（DDI）按 iOS 版本共用

**目標**：同一個 iOS 版本的 DDI 只存一份，不再每筆交易各存一份。

**規則**
- 新增共用快取 `GoFly/state/support-cache/<method>/<osVersion>-<manifestSHA256>/`，
  依 `validate_generation` 的結果驗證後才能使用。
- 交易的 `support/` 改成從快取以 clone（APFS `clonefile`，不佔額外空間）或驗證後的硬連結建立；
  journal 紀錄的 `inputManifestSHA256`、`inputFiles` 不變，掛載前的驗證流程不變。
- 快取只保留最近使用的 2 個 iOS 版本；被現行交易引用的版本不清。
- cryptex 的 `.actual` 副本一併改成 clone，或確認可以不另外存一份。

**驗收條件**
- 同一支手機、同一 iOS 版本續簽多次，`support-cache` 裡只有一份該版本映像，
  各交易的 `support/` 不增加實際磁碟用量（以 `du` 驗證）。
- 快取檔案被竄改時 `validate_generation` 失敗，流程 fail closed 並重新取得，不會掛載錯誤的映像。
- iOS 升版後會取得新版映像，舊版只在超過保留數量時才清掉。

## RET-3 一次性清理既有累積

**目標**：已經升級的使用者，舊交易的大型產物也能被回收。

**規則**
- 第一次執行含 RET-1 的版本時，對所有既有封存交易套用 RET-1 規則。
- 沒有封存 journal、也不是現行交易的資料夾（狀態不明）一律**不動**，只寫入紀錄。

**驗收條件**
- 從有大量舊交易的 state 升級後，空間降到 RET-1 的上限，配對與 journal 全部保留。
- 狀態不明的資料夾維持原樣。

## RET-4 規格與文件同步

- `MAC-INSTALLER-SPEC.md` §5.4 補上保留策略：哪些交易保留完整產物、哪些只留證據、清理時機與失敗行為。
- `AI-INSTALL.md` 註明 `transactions/` 舊交易的大型產物和超出上限的舊 journal 會被自動回收，不需要也不可手動刪除。
- AGENTS.md「iOS 實機測試安裝」節：把「journal 歷史……不刪、不搬」改為「journal 歷史依保留策略自動回收，不可手動刪除」。
  **只在 RET-6 實作完成時才改**，避免規則先於實作。
- 驗收：文件規則和 RET-1 到 RET-3、RET-6 的實作一致。

## RET-5（可選）保留 DerivedData 做增量編譯

**目標**：縮短安裝等待時間。這是速度問題，不影響空間累積。

**做法**：`build/derived` 不再每次刪除，改為以 Team ID、bundle ID 與 Xcode 版本為 key 保留一份；
`build/project` 仍每次重新複製，維持來源一致性。

**取捨**：一份 DerivedData 會長期佔用空間（通常 1GB 以上），換取重複建置變快。

**驗收條件**
- 第二次安裝的建置時間明顯短於第一次。
- 換 Xcode 版本或 Team 時快取失效並完整重建。
- 產出的 App 仍通過現有的簽章與產物完整性驗證。

## RET-6 journal 歷史回收

**目標**：封存的交易紀錄也有數量與時間上限，`transactions/` 不會無限增加資料夾。

**規則**
- 回收單位是**整筆交易資料夾**（journal、`pruned.json`、配對檔一起），不單獨刪 journal 留下孤兒資料夾。
- 一律保留，不論多舊：
  - 現行交易（`journal.json` 指向的那筆）。
  - 現行 journal 的 Wi‑Fi 配對來源交易（`intent.pairingSourceSetupID`）。
  - 每支裝置（`deviceID`）最近一筆 `journal.completed.json` 的交易。
  - 還有未處理交接檔的交易：隔離中的 `incoming.plist`、`.consuming`、交易根目錄未符合已知命名的 `.staging`，或狀態不明。
- 其餘已封存交易：保留最近 **10 筆**，以及最近 **90 天**內的；兩者都不符合才刪。
  數字先用這組預設值，實作時集中定義成常數。
- 刪除前先在 `state/retention-log.jsonl` 追加一行摘要（setupID、deviceID、mode、結果、建立與封存時間、
  配對 SHA-256），保留可追溯紀錄但不保留完整 journal。這個 log 本身只保留最近 1000 行。
- 刪除方式：先原子 rename 成 `transactions/.deleting-<setupID>`，再刪除；中途失敗時下次清理繼續處理 `.deleting-*`。

**時機**：跟 RET-1 同一次清理，持有 `operation.lock`，在 RET-1 之後執行。失敗不影響安裝結果。

**驗收條件**
- 連續安裝或續簽 30 次後，`transactions/` 只剩上列「一律保留」加最近 10 筆或 90 天內的交易。
- 清理後 Wi‑Fi 延長簽名仍然成功（來源配對所在的交易未被刪除）。
- 兩支手機交替安裝時，每支手機最近一筆成功交易都保留。
- 有隔離交接檔或狀態不明的交易不會被刪，並寫入紀錄。
- `retention-log.jsonl` 對每筆被刪的交易都有一行摘要。
- 在 rename 之後、刪除之前模擬中斷，下次清理會完成刪除，不會留下半刪的交易被當成有效交易。

## 建議順序

RET-1 → RET-3 → RET-4 先做，可以立刻止住空間累積。RET-6 接著做，並在完成時更新 AGENTS.md 的 journal 規則。
RET-2 改動掛載輸入路徑，風險較高，排在後面。RET-5 視需要再做。
