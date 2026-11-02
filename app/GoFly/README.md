# GoFly GPS iOS

**開發狀態（2026-11-02）：GoFly GPS iOS App 已開發完成。** 本專案為正式 GoFly GPS 的獨立 iOS App，部署目標 iOS 26，App bundle 依簽署 Team ID 產生為 `com.neven.gofly.<teamid 小寫>`。原 `LocalGo` 專案中 GoFly GPS 編譯用到的共用檔案已搬入本專案。

已完成功能涵蓋地圖與搜尋、瞬移、路線規劃與 GPX 匯入、搖桿、自動漫步、最愛與已存路線、連線狀態與復原、背景運行設定，以及英文、繁體中文與簡體中文。安裝支援正式 Mac 安裝與配對交接，也可透過 SideStore／AltStore 安裝 IPA 並匯入本機配對檔。使用者安裝說明見[專案 README](../../README.zh-Hant.md)。

開發完成與實機驗證分開記錄。2026-11-02 已用 SideStore 安裝的版本在 iPhone 15 Pro 驗證配對匯入、瞬移與路線背景移動，使用者亦回報手機重開機後仍可定位；自動漫步在背景偶爾被 iOS 暫停的問題已修正（背景中一段走完時原地等待下一條道路規劃，不再暫停），使用者已實機測試成功；之後仍回報偶爾在滑到背景時暫停：前景一段走完時原本會暫停 lease 並收回背景任務，剛好在規劃下一段時離開 App 就無法重新送出。2026-11-02 改為前景換段也原地等待、保留背景任務，且離開前景不取消這段規劃（`swift test` 通過，實機待驗）。同日實機 log 確認：漫步走幾秒後再切到其他 App 可在背景持續寫入；按開始後約 1 秒內離開仍會暫停（背景任務要等第一筆寫入 ACK 才申請），已改為瞬移到起點後立即寫入第一筆（瞬移、路線、漫步統一：開始與繼續的第一筆都立即寫入）；暫停數分鐘後按繼續出現「繼續失敗」（舊連線已被 iOS 斷開），已改為瞬移、路線、搖桿、漫步每次繼續都先重建連線（`swift test` 通過，實機待驗）；尚未與 Mac 安裝版在相同情境比對。完整紀錄見 [iOS 規格的安裝入口與實機驗證](../../docs/IOS-UI-DESIGN.md#兩種安裝入口2026-11-02)。乾淨 Mac 驗收與長時間實機測試仍待完成。

開啟 `GoFly.xcodeproj` 的 GoFly GPS scheme。原生裝置庫只有 arm64 iPhone slice；模擬器可驗介面，裝置操作如實回報需要實機，不能用來驗證定位服務。

## 建置與檢查

從專案根目錄執行：

```sh
bash app/GoFly/scripts/check.sh
```

`check.sh` 把衍生輸出放到根目錄 `work/gofly-ios`，預設執行核心測試與 unsigned simulator build，不簽署、不安裝到手機。加上 `--device` 才會重建原生程式庫、核對 native patch 與 Swift shim 宣告數，並執行 unsigned device build。Xcode 預設使用 `/Applications/Xcode.app/Contents/Developer`，可由 `DEVELOPER_DIR` 指定。

首次原生建置需要 Apple Silicon、可用的固定 idevice 來源 checkout，以及下載 Rust 工具鏈與鎖定依賴的網路。來源位置、工具鏈隔離與建置步驟見 [NativeBridge](NativeBridge/README.md)。原生 patch 或 shim 不符時，device 驗證直接失敗。

## 裝置準備與驗收界線

新 bundle 有獨立私有資料空間。Mac 的 target profile、配對交付及必要 DDI 準備須對準新 bundle，且在同機確認 App／配對／必要支援就緒後才宣告完成。原有 prototype 的安裝與配對不會自動出現在這個 App；手機端不下載 DDI。

建置、host 測試及模擬器畫面均不證明真機服務或接收 App 位置已正確。個別裝置驗收仍須核對已備妥裝置 Start 不送點、Stop／clear 三段結果、逾時後修復，以及拔 USB／停止 Mac 後的行為；未取得證據的項目維持 verification-pending，不影響已記錄的軟體開發完成狀態。

規格：[架構](ARCHITECTURE.md)、[視覺方向](../../DESIGN.md)、[iOS UI 設計與驗收](../../docs/IOS-UI-DESIGN.md)。早期開發票單及驗收安排位於根目錄 `.scratch/gofly-ios`，屬歷史紀錄；目前開發狀態以上方說明為準。

## 來源

三個精確沿用的 StikDebug setup 來源及 AGPL-3.0 授權雜湊見 `NativeSources.json`。原生 idevice 採 MIT 授權，固定 upstream commit、鎖定依賴及 GoFly GPS verify-only 修改見 `NativeBridge`；Swift 僅匯入經審查的窄 header。AGPL-3.0、idevice MIT 與來源註記隨 App 放入 Legal。授權與來源稽核狀態見[授權說明](../../docs/LICENSING.md)；軟體開發完成不代表授權稽核或所有裝置驗收均已完成。


## Mac 正式首次安裝與啟動交接（M1）

Mac 依選取的 Team ID 建置 `com.neven.gofly.<teamid 小寫>`，並以相同 Bundle ID 完成首次安裝、一次性配對匯入與必要裝置支援。舊 `com.neven.gofly` 會成為另一個 App，資料不會自動帶過去。iOS 首次啟動直接顯示 onboarding 歡迎頁，底部在「下一步」上方顯示 loading indicator；交接檢查完成前停用下一步，不建立正常服務、任務及資料商店。通過後才開放使用者按下一步，失敗或等待 Mac 時保留必要提示。沒有正式交接狀態仍可一般啟動，缺少／錯誤的正式資料不回退到舊支援。此介面更新的實機驗收仍待確認。

交接資料不代表 VPN、GPS、clear 或移動已成功。正式 activation 存在時不再消耗無關的舊 v1 輸入；消耗本次 v1 時在實際解碼後核對交易 ID，不因相同配對 bytes 接受另一筆交易。設定頁以背景唯讀觀察的快取顯示配對狀態，畫面求值不讀配對檔。共享 v1 API 只增加可選交易核對，舊呼叫格式相容，沒有新增 native FFI 或重建原生程式庫。

M1 的最終軟體驗證與限制見[首次安裝票](../../.scratch/gofly-ios/issues/M1-first-install.md)；所有手機步驟見[集中驗收](../../.scratch/gofly-ios/DEVICE-ACCEPTANCE.md)。安裝完成不解除冷啟動待確認，也不自動送點；支援資料由 Mac 準備，手機不另行下載。
