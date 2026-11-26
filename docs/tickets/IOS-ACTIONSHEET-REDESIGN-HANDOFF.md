# Handoff：iOS ActionSheet 重新設計（Figma 審查）

日期：2026-11-26
狀態：**審查完成並已於 Figma 修正（含補齊 Dark · E6 `410:18105`），已同步 `docs/IOS-UI-DESIGN.md` 與 App UI（`GoFlyActionSheet.swift`）**，未實機驗收。
審查者：Gemini（Antigravity）

## 1. 背景與問題

實機回報（D12 已匯入路線動作選單、E6 漫步中搜尋地點選單）：action sheet 的**標題與選項難以區分**。

舊設計／現行 App（`app/GoFly/App/GoFlyActionSheet.swift`）：

- 標題置中，與選項同樣置中、同色系；App 實作用 15 pt semibold 主文字色，看起來像另一個選項。
- 標題下方分隔線在 Figma 用卡片底色（看不見），只靠留白區隔。
- 選項 56 pt 高、置中純文字，無圖示。

## 2. 設計來源

- Figma 檔：`RtPV8PXCQJ2WXK3jk3kPrq`（GoFly · UI 線框討論）
- 頁面：`04 · iOS Redesign（Google Maps 參考）` node `121:50359` — iOS 唯一視覺準據
- 舊頁 `01 · iOS App` 已廢棄，勿參考。

| 節點 | ID | 說明 |
|---|---|---|
| Component `ActionSheet / 路線動作`（Light） | `313:30389` | Light Components board |
| Component `ActionSheet / 路線動作`（Dark） | `322:37495` | Dark Components board |
| D12 · 點選路線 / 動作選單（Light） | `123:61268` | 內含 instance `313:30405` |
| Dark · D12 · 點選路線 / 動作選單 | `322:40800` | 內含 instance `322:40810` |
| E6 · 漫步中搜尋地點 / 動作選單（Light） | `404:16327` | sheet 為一般 frame `404:16377`（非 instance） |

## 3. 新設計規格

卡片

- 寬 361（螢幕左右 16 pt）、圓角 14、填色 `color/surface/card`，底部內距 6 pt。
- 與獨立「取消」按鈕間距 8 pt（sheet 底緣 = 取消頂緣 − 8）。

標題區（Header）

- 靠左；內距 上 16／左右 20／下 14；標題與說明間距 2。
- 標題：`Theme/subheadlineEmphasis`（15 pt Semibold），`color/text/primary`。
- 說明（選填）：`Theme/footnote`（13 pt Regular），`color/text/secondary`。
- 標題區下方整寬 1 pt 分隔線，`color/line/separator`（Header Divider）。

選項列（Action）

- 高 52 pt、靠左；內距左右 20；圖示與文字間距 14。
- 圖示 22 pt，`color/icon/secondary`；文字 `Theme/body`（17 pt Regular），`color/text/primary`。
- 列間分隔線 1 pt，從左 56 pt（文字起點）延伸到右緣。
- 破壞性選項（刪除）：圖示 `color/icon/danger`、文字 `color/text/danger`。

圖示對應

| 選項 | 圖示元件 |
|---|---|
| 載入路線 | `icon/play` |
| 查看全部點位 | `icon/route-list` |
| 匯出路線 | `icon/external-link` |
| 刪除路線 | `icon/trash` |
| 瞬移 | `icon/nav` |
| 指定地點 | `icon/flag` |

規格文字已同步到 `docs/IOS-UI-DESIGN.md` D11／D12 段（「ActionSheet 元件（D12／E6 共用）」），E6 App 實作段已標註為重新設計前的舊實作。

## 4. 請審查的重點

1. **可辨識性**：標題區與選項是否一眼可分（對齊、字級、分隔線、前置圖示）。
2. **與 04 頁其他元件一致性**：圓角、間距、字型 style、顏色變數是否與同頁 sheet／列表一致。
3. **圖示語意**：上表圖示是否恰當，尤其「瞬移 → `icon/nav`」「匯出 → `icon/external-link`」。
4. **Light / Dark** 兩版 D12 對比度與層次是否足夠。
5. **觸控與無障礙**：52 pt 列高（低於舊 56 pt，仍 ≥ 44 pt）、danger 色在兩個主題的對比。
6. 有無遺漏的使用處（其他畫面若用到 ActionSheet 或類似底部動作卡）。

## 5. 已知缺口／限制

- **Figma 缺 `Dark · E6` 畫面**（Dark E 段沒有 E6），尚未補。
- E6 的 sheet 是一般 frame，不是 `ActionSheet` component 的 instance；樣式是手動同步，日後元件修改不會自動帶過去。
- 匯出截圖時曾出現綁定變數的 paint 以 fallback 黑色渲染；已把各 paint 的基礎色設成變數解析值。若看到黑卡片，請回報 node ID。
- App 程式碼未修改；`GoFlyActionSheet` 仍為舊樣式（置中、56 pt、無圖示）。`GoFlyActionSheetItem` 需新增 icon 欄位才能實作。

## 6. 審查方式

- 使用 figma-console MCP 前先載入 `figma-console-mcp` skill（preflight `figma_get_status`，以 node ID 讀取，不要 `loadAllPagesAsync`，截圖指定 frame ID）。
- 建議只截圖上表 5 個節點；審查僅讀取，**不要修改 Figma、不要張貼評論**，除非使用者另行授權。
- 回報格式：每項問題附 node ID、觀察、建議修正；區分「必須修」與「建議」。
