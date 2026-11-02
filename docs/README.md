# GoFly GPS 文件索引

本目錄保留現行規格、安裝操作與維護規則。2026-11-03 已移除舊開發票單、執行 prompt、Bug Report 修正計畫、逐頁 Figma 比對紀錄與效能交接待辦；不再依這些舊文件自動建立測試或截圖產物。

## 產品與設計

| 文件 | 用途 |
| --- | --- |
| [iOS UI 設計與驗收](IOS-UI-DESIGN.md) | iOS 畫面、互動、已確認變更及待實機驗證事項 |
| [Mac UI 設計](MAC-UI-DESIGN.md) | Mac 畫面範圍及視覺準據 |
| [Mac 安裝器規格](MAC-INSTALLER-SPEC.md) | 安裝、更新、配對交付與完成條件 |
| [iOS 文字樣式](IOS-TYPOGRAPHY.md) | 系統字型、字級與 Dynamic Type |
| [iOS 色彩資料](IOS-COLOR-SCHEME.json) | 語意色與 Light／Dark 對應 |
| [Status Pill 錯誤清單](IOS-STATUS-ERRORS.md) | 狀態定義、錯誤來源及顯示文案 |
| [錯誤 Toast 文案](IOS-ERROR-TOAST-COPY.md) | 錯誤訊息及修復動作 |
| [命名規範](BRANDING.md) | GoFly GPS／GoFly 的名稱用法 |
| [Session 架構決策](adr/0001-event-driven-session-liveness.md) | 連線存活、心跳與自動重連契約 |

iOS 視覺以 Figma `04 · iOS Redesign（Google Maps 參考）`，Mac 以 `05 · Mac Redesign（新版）` 的目前渲染畫面為準；入口與規則見 [AGENTS.md](../AGENTS.md)。本次文件清理未重新檢查 Figma 或實機，不代表設計、程式與裝置驗收已全部一致。

## 安裝、打包與維護

| 文件 | 用途 |
| --- | --- |
| [安裝操作說明](AI-INSTALL.md) | Release 安裝與維護者實機安裝流程 |
| [iOS 打包說明](../app/GoFly/README.md) | 原生庫準備與 IPA 打包 |
| [Mac 開發與打包說明](../app/GoFlyMac/DEVELOPMENT.md) | App／DMG 建置及產物校驗 |
| [升版規則](VERSIONING.md) | 版本號與 build 的授權及遞增方式 |
| [Release 撰寫規格](RELEASE-NOTES.md) | Release 說明的語言與格式 |
| [授權說明](LICENSING.md) | 授權範圍、第三方來源與限制 |

目前預設只執行 IPA／DMG 打包必要校驗。獨立測試、模擬器、UI 截圖與 `.xcresult` 須使用者另行要求；必要建置中間檔重用固定目錄，成品放在 `work/dist`。

## 狀態與證據

規格內的日期、測試數量與交付紀錄是歷史描述，不是待執行指令。同主題的後續明確更新取代早期規則；若仍有衝突，依平台目前 Figma 渲染與使用者已確認需求核對，不能由舊待辦推定目前狀態。

刪除舊計畫不代表其中所有待辦已實作或驗收。已清除的 `work/` 截圖、測試報告及舊 tracker 不再作為可讀取的證據。GPS／VPN、背景移動、VoiceOver、觸覺、乾淨 Mac 安裝與資料保留等未驗事項，仍須實際觀察後才能更新為通過。
