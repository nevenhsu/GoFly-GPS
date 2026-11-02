# GoFly Mac V1 UI 設計與實作現況

正式品牌標題使用 GoFly GPS，App 內一般句子保留 GoFly，README 統一使用 GoFly GPS；詳見 [命名規範](BRANDING.md)（2026-11-02）。識別碼與技術路徑維持相容。

更新日期：2026-10-27。Mac App 的唯一視覺準據是 Figma 檔 `RtPV8PXCQJ2WXK3jk3kPrq` 的 `05 · Mac Redesign（新版）`（頁面 `123:61504`），只採用 V1 的 E Mac 環境、D 裝置及對應 Dark sections。灰字說明是操作行為規則；舊 `02 · Mac App`、早期 Mac 改版畫面及 `Archive ·` sections 不作準據。

流程與驗收規格見 [`MAC-INSTALLER-SPEC.md`](MAC-INSTALLER-SPEC.md)，逐票實作、軟體證據與未驗項目見 [Mac V1 TRACKER](../.scratch/gofly-mac-v1/TRACKER.md)。

## V1 實作範圍

- E00–E09：啟動路由、全新 Mac 環境步驟與環境檢查結果。
- D01–D14：裝置側欄、首次 USB 安裝、USB／Wi-Fi renew、自動 renew、完成、找不到 Wi-Fi 裝置及重新開始。
- 第 1 版不含備份、還原、重置或交易接續。中斷後以新 setupID 從頭重新開始。
- SwiftUI 畫面使用系統淺／深外觀、macOS 系統字體與 SF Symbols；版面、文案和狀態以當前 Figma V1 渲染稿及畫面下方說明為準。

## Mac 專屬色彩系統

所有 Mac 色彩角色集中於 [`MacColorSystem.swift`](../app/GoFlyMac/Sources/GoFlyMac/MacColorSystem.swift)，由 `GoFlyStyle` 暴露畫布、側欄、卡片、文字、分隔線、互動、品牌及狀態語意 token。色彩跟隨 macOS 外觀；View 不自行定義色碼。這套 Mac palette 不匯入或共用 iOS 色彩程式。V1 沒有 theme 選擇器；更換 Mac theme 時集中修改這套 palette，再核對淺色與深色截圖。

## 證據與限制

- E00–E09 與 D01–D14 的截圖保存在 `work/gofly-mac/v1/screens/`；逐畫面 Figma 比對紀錄在 Tracker。截圖代表本機 capture fixture，不是手機操作證據。
- `swift test` 與 Bridge unittest 的離線結果只驗證軟體路徑。Wi-Fi 真機 renew、自動 renew 與通知、實際睡眠抑制、免費 Team capability、資料保留、乾淨 Mac／另一個帳號下載安裝，均需按 [`MAC-DEVICE-ACCEPTANCE.md`](../.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md) 實測。
- DMG 的本機建置與隔離模擬結果記在 Tracker。尚無公開 DMG、Developer ID 簽署或 notarization；不能將本機產物描述為正式公開發行。

Figma Archive sections 保留為歷史稿；只有 V1 實作完成且使用者確認後才刪除。
