# Figma Bridge Autostart

macOS 背景程式每 5 秒檢查一次。Figma Desktop 的 Design、FigJam 或 Slides 編輯器在前景，且沒有對話框、其他外掛或輸入操作時，程式會依序展開英文選單 **Plugins → Development**，再執行 **Figma Desktop Bridge**。它會等 Bridge 面板出現才確認啟動。若外掛已在同一檔案開過，手動關閉後要重啟 Figma 才會再次自動開啟。首頁及原型預覽會等待。

`main.swift` 依舊版操作紀錄重建。`AppIcon.icns` 是 1.0.2 的滿版深色底版本，採 Figma 五色及薄荷綠閃電，與已安裝 App 和 10 月 20 日備份的圖示逐位元組相同。`Info.plist` 沿用原本的執行檔名稱、Bundle ID `local.neven.figma-bridge-autostart` 和版號。

程式會對每個新 Figma 處理程序設定 Electron 的 `AXManualAccessibility`，讓 macOS 輔助使用 API 能取得編輯器的網頁結構。若編輯器仍在載入，程式會再次請求。這個設定只套用在當次的 Figma 處理程序。[Electron 無障礙文件](https://www.electronjs.org/docs/latest/tutorial/accessibility)

## 打包

在 repo 根目錄執行以下指令。需要可用的 Xcode 或 Command Line Tools。輸出為 `work/figma-bridge-autostart/Figma Bridge Autostart.app`，也可將其他輸出目錄傳給腳本。

```sh
bash scripts/figma-bridge-autostart/build.sh
```

## 更新現有安裝

備份 `~/Applications/Figma Bridge Autostart.app`，再以新打包的 App 覆蓋同一路徑。現有的 `~/Library/LaunchAgents/local.neven.figma-bridge-autostart.plist` 會使用這個路徑。更新後重啟背景程式。

```sh
launchctl kickstart -k "gui/$(id -u)/local.neven.figma-bridge-autostart"
```

如果狀態顯示 `permission-required`，到「系統設定 → 隱私權與安全性 → Device Control and Data Access（部分 macOS 版本顯示為輔助使用）」重新授權目前安裝的 App。

## 驗證

`--check` 會讀取 Figma 安裝與 Bridge 匯入狀態，輸出 JSON。它不會打開 Figma 或更新背景程式的狀態檔。

```sh
"$HOME/Applications/Figma Bridge Autostart.app/Contents/MacOS/FigmaBridgeAutostart" --check
cat "$HOME/Library/Application Support/Figma Bridge Autostart/status.json"
```

驗證實際啟動時，先用 ⌘Q 退出 Figma，從 Dock 或 Finder 正常重開，進入設計檔並將視窗留在前景。查看 Bridge 面板是否自行出現，再確認 Figma Console 的連線探測成功。驗證期間避免先用其他工具讀取 Figma 的無障礙樹，以免該工具替 Figma 啟用它。
