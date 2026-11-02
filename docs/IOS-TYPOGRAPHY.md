# iOS 文字樣式規範（Figma 04）

視覺準據是 Figma `04 · iOS Redesign（Google Maps 參考）` 的渲染畫面與 `0 · 共用元件（Typography）` 中的 `Theme/*` 樣式。App 一律使用 iOS 系統字型；Figma 的 PingFang TC 由 iOS 系統字型自動對應。字型、顏色與 Light／Dark 外觀分開管理，文字顏色由 `GoFlyTextColor` 對應的語意 token 提供，色值快照見 [IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json)。

Figma 有 14 個核心文字樣式與 2 個按鈕樣式。所有樣式均使用 Regular 或 Semibold，不使用 Medium、Bold、Light 或自訂字型。14 個核心樣式隨 Dynamic Type 縮放；`micro` 與 `metric` 固定大小。

## Figma Theme 字級

| Token | Figma style | 基準大小 | 字重 | 主要用途 |
| :-- | :-- | --: | :-- | :-- |
| `display` | `Theme/display` | 28 pt | Semibold | 首次引導與設定頁大標題 |
| `title` | `Theme/title` | 20 pt | Semibold | 面板、卡片與導航卡標題 |
| `wheel` | `Theme/wheel` | 22 pt | Regular | F6.a 時間選擇 wheel 數字 |
| `headline` | `Theme/headline` | 17 pt | Semibold | 頁面、對話框與區段標題 |
| `body` | `Theme/body` | 17 pt | Regular | 清單列、輸入值與一般內文 |
| `bodyEmphasis` | `Theme/bodyEmphasis` | 17 pt | Semibold | 主要按鈕與強調內文 |
| `subheadline` | `Theme/subheadline` | 15 pt | Regular | 次要文字、欄位 placeholder |
| `subheadlineEmphasis` | `Theme/subheadlineEmphasis` | 15 pt | Semibold | Toast 標題／操作、Chip 與精簡按鈕 |
| `footnote` | `Theme/footnote` | 13 pt | Regular | 副標、Toast 說明、地址與百分比 |
| `footnoteEmphasis` | `Theme/footnoteEmphasis` | 13 pt | Semibold | StatusPill 與強調輔助文字 |
| `buttonMedium` | `Theme/button/medium` | 16 pt | Semibold | 中型按鈕標籤 |
| `buttonSmall` | `Theme/button/small` | 14 pt | Semibold | 小型按鈕標籤，如 R04 連線說明連結 |
| `caption` | `Theme/caption` | 12 pt | Regular | 角色、座標與軸線標籤 |
| `captionEmphasis` | `Theme/captionEmphasis` | 12 pt | Semibold | 強調小標 |
| `micro` | `Theme/micro` | 10 pt | Semibold | Tab Bar 標籤與羅盤方位字母；固定大小 |
| `metric` | `Theme/metric` | 36 pt | Semibold | 速度讀數；固定大小 |

## 實作規則

1. 文字使用 `.goFlyFont(GoFlyFont.<token>)`。共享 `GoFlyFontModifier` 以 `Font.system(size:weight:design:)` 使用表內精確基準大小，並用 `@ScaledMetric` 依相應系統文字樣式縮放；`micro`、`metric` 不縮放。
2. `Font.system(size:)` 直接用於圖示時只控制圖示 glyph 尺寸，不當作文字樣式。圖示資產依 Figma 04 的共用 Icon 元件規範處理。
3. View 不直接指定文字字級、字重或文字顏色。只使用 Regular／Semibold；顏色透過 `GoFlyTextColor` 角色及 共用 Theme token。
4. `GoFlyTextColor` 有 9 個語意色彩值；`inverse` 與 `onDark` 以不同用途名稱共用 `common/white`。其他色值與 Light／Dark 對應以 `docs/IOS-COLOR-SCHEME.json` 為準，不在本文件複製色票。
5. 新增 Figma `Theme/*` 樣式時，須同步更新本表、`GoFlyFont` 與 `TypographyStandardTests`。禁止使用 `Font.custom`、`UIFont(name:)`、字型檔或字型名稱字串。

## 驗證

`TypographyStandardTests` 檢查 16 個 Figma Theme token、基準大小與字重、系統字型實作、Dynamic Type 例外及自訂字型 API；也掃描 App 原始碼中的原生文字樣式、字重與固定字級使用。現行預設流程只執行 IPA／DMG 打包必要校驗，不自動執行此測試或逐 frame 截圖。使用者另行要求視覺驗證時，按當次範圍核對 Light／Dark 與 Dynamic Type；本文件不代表已完成視覺或實機驗證。
