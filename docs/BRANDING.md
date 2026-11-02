# GoFly GPS 命名規範

2026-11-02 起，正式產品名稱由 GoFly 改為 **GoFly GPS**；Mac 安裝器的品牌標題為 **GoFly GPS for Mac**。現有 App Logo 沿用。

## 名稱用法

- 獨立品牌標題、iOS 主畫面顯示名稱與啟動畫面使用 **GoFly GPS**；Mac 的品牌標題與 bundle 顯示名稱使用 **GoFly GPS for Mac**。
- App 內一般句子保留簡寫 **GoFly**，包含按鈕、說明、通知與權限標題，例如「允許 GoFly 使用定位」、「允許 GoFly 使用區域網路」、「安裝 GoFly」。三種語言遵循同一規則。
- README 的品牌文字統一使用 **GoFly GPS**；Mac 版使用 **GoFly GPS for Mac**。
- GitHub 倉庫更名為 `nevenhsu/GoFly-GPS`（倉庫名稱不含空格），文件中的儲存庫及 Release 連結跟隨新網址。

## 相容性

保留 Bundle ID、Xcode target／scheme、Swift module／type、資源名稱、偏好設定與資料目錄、配對與交接協定等技術識別，避免影響既有安裝與資料。發行套件使用 `GoFly-GPS-<version>.ipa` 與 `GoFly-GPS-<version>-arm64.dmg`，checksum 檔名與內容同步採用新套件名（例如 `GoFly-GPS-1.0.6.ipa.sha256`）。既有歷史套件與驗證紀錄保留原檔名。App bundle 仍為 `GoFly.app`；安裝目標仍為 `/Applications/GoFly.app`，磁碟映像掛載名稱仍為 `GoFly`。README 的路徑、指令與檔名照實保留。

## 設計與驗收狀態

本次為使用者確認的品牌更名，沿用圖示、配色與操作流程；iOS 啟動標題寬度由 120 pt 放寬為 220 pt 以容納新名稱，維持置中。已查閱 Figma `04 · iOS Redesign` 的 R01 與 `05 · Mac Redesign（新版）` 的 E01 渲染；兩頁目前仍顯示舊品牌，Figma 線框、歷史截圖與歷史驗證紀錄尚未同步，不得宣稱已更新。

來源驗收：品牌標題與 App 顯示名稱使用全名，一般句子保留簡寫；README Logo 路徑有效，技術識別與安裝路徑保持相容。建置、打包、iOS 主畫面顯示、Mac 選單顯示與新標題的文字截斷情況，仍須在後續建置／裝置驗證時確認；本次來源修改不代表已安裝或發布。
