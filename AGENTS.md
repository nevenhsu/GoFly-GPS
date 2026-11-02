# Project instructions

## UI 設計稿準據規範（永久最高優先・禁止反覆詢問或要求使用者提醒）

- **iOS UI 主要設計稿唯一準據**：Figma 頁面 `04 · iOS Redesign（Google Maps 參考）`（node-id: `121-50359`）。
  連結：https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359
  - **核心準則**：所有 iOS App 介面實作、UI 修復、畫面佈局、元件、顏色、間距、圖示與視覺呈現，**一律且唯一以「04 · iOS Redesign（Google Maps 參考）」的渲染畫面為視覺最高權威（Visual Authority）**。
  - **禁止事項**：舊頁面 `01 · iOS App`（`13-2098`）與過往舊線框已全面廢棄，嚴禁引用或作參考。任何情況下都不要要求使用者重複提醒「iOS UI 要看 04 頁面」。
  - **衝突裁決**：當任何舊文件或規格文字與「04 · iOS Redesign」的渲染畫面有差異或衝突時，無條件以 04 頁面渲染畫面為準，並在當前任務中同步修正規格。
- **Mac UI 主要設計稿**：Figma 頁面 `05 · Mac Redesign（新版）`（node-id: `123-61504`）。
  連結：https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=123-61504
- **共用基礎元件庫**：`00 · 品牌與基礎元件`。

This workspace contains the local REA research environment. The research target
and implementation specification have not been selected yet.

- Follow the user's current request and preserve unrelated work.
- When confirmed design or interaction requirements change, including Figma-only
  work, update the related development specifications, terminology, and acceptance
  criteria in the same task. Replace superseded rules and distinguish design
  updates from implemented behavior and device verification.
- Before every GoFly UI implementation or wireframe task, consult the platform redesign page in the GoFly UI Figma file (`RtPV8PXCQJ2WXK3jk3kPrq`): iOS uses `04 · iOS Redesign（Google Maps 參考）` (`121-50359`), Mac uses `05 · Mac Redesign（新版）` (`123-61504`). Shared components live in `00 · 品牌與基礎元件`; pages `01 · iOS App` and `02 · Mac App` are superseded.
  Treat the current platform page's rendered designs as the visual authority.
  When a rendered design conflicts with documentation, update the related spec
  and acceptance criteria in the same task. Record missing or conflicting Figma
  variants instead of claiming they are designed. Use platform specs for
  behavior and accessibility; project safety and device-operation rules still
  govern actual operations.
- Any task that uses the figma-console MCP must first load and follow the
  `figma-console-mcp` skill (preflight with `figma_get_status`, parallel reads,
  `figma_batch_*` writes, screenshot verification capped at 3 iterations).
- Figma work is currently limited to UI/UX wireframes. Unless the user explicitly
  requests prototypes again, do not add prototype wiring, interaction tests, or
  combinatorial state screens. Keep only the wireframes needed for discussion.
- When preparing a GoFly Figma Bug Report fix list, use Figma Console to read the
  comments and inspect each attached screenshot; map feedback to the screenshot
  and compare it with the current platform redesign page. Keep comments from
  other pages out of scope unless requested. Group duplicate reports, distinguish
  observed device behavior from proposed fixes, and call out conflicting comments
  or design variants. Check relevant Git history and the current working-tree
  diff before listing work: mark committed changes as implemented only when the
  evidence supports it, and treat uncommitted changes as in progress rather than
  complete. Present remaining items with their evidence and acceptance criteria;
  separate adjacent or out-of-scope reports. If asked only to list or plan fixes,
  do not implement them.
- Source `scripts/env.sh` for the project's JDK 21 and Ghidra paths.
- For reverse-engineering tasks, read `tools/reverse-skill/README_AI.md`,
  `tools/reverse-skill/RULES.md`, and `tools/reverse-skill/skills/SKILL.md`.
  Resolve package-relative references from that repository, and invoke its
  scripts through their actual paths under `tools/reverse-skill/skills/scripts/`.
- Reverse-skill is shared with Codex and Claude through the
  `~/.agents/skills/reverse-skill-router` symlink. Keep package rules in the
  skill rather than copying them into global agent rules.
- Use REA for analysis and preserve evidence and unknowns under `work/`.
- Choose target-specific tools after the user selects a target. PentAGI model
  credentials and testing scope must be configured before a security test.
- Keep credentials and generated research output out of version control.
- Do not run Prettier unless explicitly requested.
- **不要自動升版號或 build。** 只有使用者明確要求時才修改；重新建置、打包 IPA／DMG、合併或發布不代表升版授權。獲授權後遵循 [升版規則](docs/VERSIONING.md)：iOS 新的 `MARKETING_VERSION` 可從 build 1 開始，同版 build 遞增；Mac build 跨版本持續遞增、不歸零。

- GitHub Release 說明遵循 [Release 撰寫規格](docs/RELEASE-NOTES.md)：英文在前、繁中在後，不加語言標籤；開頭的版本／build 摘要只出現一次，中英文同步更新並在發布後讀回核對。

## iOS 實機測試安裝

- 實機測試安裝／更新一律使用 `bash scripts/install-ios-test.sh`，或相同的正式 Mac setup producer；不可只執行 Xcode／`devicectl install` 後宣告完成。先核對 USB 裝置與 Xcode 登入帳號，再執行唯讀 `--action preflight`；取得使用者安裝授權後才執行 `--action apply`。
- 此 producer 的固定 `pymobiledevice3` 版本需要讀取系統 `/var/run/usbmuxd`。受限命令列會因 `PermissionError` 把實際裝置誤報為 `device-disconnected`，即使 Xcode Device Hub 看得到手機。Codex 中從第一次唯讀 `preflight` 起，及後續 `apply`，都要用 `sandbox_permissions: "require_escalated"` 執行正式腳本；不要先在受限模式重試，也不要改用 `sudo` 或另一套安裝命令。若升權遭拒，停止並回報阻礙。
- 簽署 Team 不寫死：每次安裝前以 `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` 讀取 Xcode 目前登入帳號的 Team ID，並明確傳入 `--team`；若有多個 Team 或讀不到，停止並詢問使用者，不自行猜測、不沿用舊 Team。曾淘汰的舊 Team `NHW5EDBH4P` 與 `48XD59469V` 不再固定使用。使用者授權 Apple 佈建更新時，`--allow-provisioning-updates` 必須同時帶在 `preflight` 與 `apply`。
- 首次 `--mode install`；已有 App 使用 `--mode renew` 覆蓋更新並保留資料。兩者都須確認 App、這支手機的配對匯入與必要裝置支援；重新簽名／更新也不能略過配對。不卸載、不清除偏好設定／最愛／路線。只有 `complete=true` 且 `installationConfirmed`、`pairingImported`、`supportObserved` 全為 true 才算完成。
- 寫入中斷後**不沿用舊交易**：從頭建立新的 `setupID`，重新執行 `--action preflight` → `--action apply`（已有 App 用 renew 覆蓋並保留資料，USB 配對重新產生；見 `docs/MAC-INSTALLER-SPEC.md` §5.4）。producer 只有一筆全域現行交易；`apply` 遇到未完成交易會封存為 `journal.abandoned.json`、保留原交易資料並建立新交易；重送相同 setupID 仍衝突。iOS 在讀取／匯入前，先以原子 rename 將 `incoming.plist` 認領為 `incoming.plist.consuming`；producer 也以原子 rename 隔離舊交易的 `incoming.plist`，只驗證及移除完全吻合交易 ID、裝置 ID、pairing bytes 與 SHA-256 的隔離檔。看到 `.consuming` 或不確定的狀態時 fail closed。活動 `PairingFileStore`、activation receipt、journal 歷史、App 與使用者資料不刪、不搬；不可手動刪除 journal、配對或 App。操作範例與限制見 `docs/AI-INSTALL.md`；可直接交給 AI 的覆蓋安裝任務 prompt 位於該文件的 `iOS device-test prompt` 節。
