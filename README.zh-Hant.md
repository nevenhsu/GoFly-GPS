# GoFly

[English](README.md) · **繁體中文** · [简体中文](README.zh-Hans.md)

GoFly 是一個讓你在自己的 iPhone 上選擇並移動模擬 GPS 位置的 App。**GoFly for Mac** 使用你在 Xcode 登入的 Apple 帳號，透過 USB 安裝 iPhone App，並可更新簽名，讓 App 持續可用。

[**下載最新版 GoFly for Mac（DMG）**](https://github.com/nevenhsu/GoFly/releases/latest)

**開發狀態（2026-11-02）：GoFly iOS App 已開發完成。** 可透過 GoFly for Mac 安裝，或使用 SideStore／AltStore 安裝 IPA。已知限制與尚待驗證項目見下方說明。

## iPhone App 的功能

**Light 外觀**

<div style="overflow-x: auto; white-space: nowrap;">
  <img src="docs/images/ios/map-teleport.png" alt="地圖與瞬移" width="180">&nbsp;&nbsp;<img src="docs/images/ios/routes.png" alt="路線規劃" width="180">&nbsp;&nbsp;<img src="docs/images/ios/joystick.png" alt="搖桿與漫步" width="180">
</div>

<br>

**Dark 外觀**

<div style="overflow-x: auto; white-space: nowrap;">
  <img src="docs/images/ios/map-teleport-dark.png" alt="地圖與瞬移" width="180">&nbsp;&nbsp;<img src="docs/images/ios/routes-dark.png" alt="路線規劃" width="180">&nbsp;&nbsp;<img src="docs/images/ios/joystick-dark.png" alt="搖桿與漫步" width="180">
</div>

<br>

- **地圖與搜尋**：搜尋地點並跳轉過去，介面參考 Google Maps 的版面。
- **瞬移**：把模擬位置移到指定的點，並維持在那裡。
- **路線**：在多個點之間規劃路線（含道路路線）、儲存、匯入 GPX，並以步行、自行車、機車或汽車的速度執行。
- **搖桿**：用畫面上的搖桿手動操控移動。
- **漫步**：沿著道路自動行走，可隨時手動接管。
- **最愛與已存路線**：保存在手機上，重新簽名時資料會保留。
- **狀態與復原**：狀態膠囊顯示連線狀態；App 會自動重新連線，也可手動重試、停止或**還原真實 GPS**。
- **語言**：英文、繁體中文、簡體中文。

裝置通道使用 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，需另外從 App Store 安裝。

## Mac App 的功能

GoFly for Mac 不是定位工具。它用**你的** Xcode 簽名 Team 建置 iPhone App、安裝到你連接的 iPhone、交付 iPhone App 需要的配對與裝置支援，並且要等 iPhone 回報後才顯示完成。之後可以經由 USB 或 Wi‑Fi **延長簽名**；Mac App 開著時，簽名快到期會自動延長。延長簽名時 App 內的資料會保留。

## 需求

| 項目 | 需求 |
| --- | --- |
| Mac | Apple Silicon，macOS 15 以上（需符合你 Xcode 的要求）。 |
| Xcode | 從 App Store 安裝完整 Xcode 並下載 iOS 平台。全新 Mac 上 GoFly 會逐步引導。 |
| Apple 帳號 | 你自己的帳號，在 Xcode → Settings → Apple Accounts 登入。免費 Personal Team 即可。GoFly 不會取得你的密碼。 |
| iPhone | iOS 26 以上、已解鎖；首次安裝需 USB 資料線、開啟**開發者模式**，並信任這部 Mac。 |
| iPhone App | 已安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) 並允許新增 VPN。 |
| 網路 | Apple 簽名與地圖搜尋需要。 |

免費 Personal Team 的簽名通常約七天到期；讓 Mac App 保持開啟會自動延長，也可按 **Renew Signing**。Mac App 顯示的到期日在你於自己的裝置驗證前，僅供參考。

## 安裝（DMG）

1. 到[最新版 Release](https://github.com/nevenhsu/GoFly/releases/latest)，把 `GoFly-<版本>-arm64.dmg` 與 `GoFly-<版本>-arm64.dmg.sha256` 下載到同一個資料夾。
2. 核對下載檔案，結果必須是 `OK`：

   ```sh
   shasum -a 256 -c GoFly-1.0.0-arm64.dmg.sha256
   ```
3. 開啟 DMG，然後**在「終端機」執行安裝腳本**（macOS 會擋下雙擊 `install.sh`）：

   ```sh
   bash /Volumes/GoFly/install.sh
   ```

   它只會安裝 `/Applications/GoFly.app`，已有舊版時會先詢問，並移除該 App 的下載隔離屬性後開啟。不使用 `sudo`、不更動 Gatekeeper、不動 GoFly 的資料。出現提示時輸入 `y` 並按 **Enter**。
4. 在 GoFly for Mac 依畫面步驟準備 Xcode，然後用 USB 連接 iPhone、信任這部 Mac、開啟開發者模式，按**安裝 GoFly**。
5. 在 iPhone 上信任開發者（設定 › 一般 › VPN 與裝置管理）、安裝並允許 LocalDevVPN，再開啟 GoFly。Mac App 讀回 iPhone 的確認後才算完成。

這個 App 使用 ad-hoc 簽署、**未經公證**，所以不能直接雙擊開啟，請用上面的安裝腳本。若你自己拖曳 App，請執行 `xattr -dr com.apple.quarantine /Applications/GoFly.app`。

## 用 SideStore 或 AltStore 安裝 IPA

不想用 Mac App 時，可以用 [SideStore](https://sidestore.io) 或 [AltStore](https://altstore.io) 以你自己的 Apple ID 重新簽名並安裝 IPA。兩者使用同一份 IPA，第一次開啟時要匯入這支 iPhone 的配對檔。

**準備**

- iPhone：iOS 26 以上，已開啟**開發者模式**。
- 已安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) 並允許新增 VPN；使用 GoFly 時連上 Wi‑Fi。
- 一台電腦，用 [iloader](https://github.com/nab138/iloader) 匯出這支 iPhone 的配對檔（`pairingFile.plist`）。

**安裝**

1. 從[最新版 Release](https://github.com/nevenhsu/GoFly/releases/latest)下載 `GoFly-<版本>.ipa`（可用同名 `.sha256` 核對），傳到 iPhone。
2. 選一個側載工具安裝：
   - **SideStore**：依[官方流程](https://docs.sidestore.io/docs/installation/install)完成設定，保持 Wi‑Fi 與 LocalDevVPN 連線，在 **My Apps → ＋** 選這個 IPA。
   - **AltStore**：依 [AltStore 說明](https://faq.altstore.io/)在電腦安裝 AltServer、在 iPhone 安裝 AltStore，再在 **My Apps → ＋** 選這個 IPA。
3. 免費 Apple ID 的簽名約 7 天，請讓 SideStore／AltStore 定期重新整理；重新整理會保留 App 內的資料。

**第一次開啟**

1. GoFly 會顯示「匯入配對檔」。在電腦用 iloader 匯出這支 iPhone 的配對檔，傳到 iPhone（AirDrop 或「檔案」App），點**匯入配對檔**選取。
2. 依序允許定位與區域網路，並連上 LocalDevVPN，就可以開始使用。

配對檔必須屬於這支 iPhone；其他手機的配對檔會在第一次連線時被擋下。IPA 版不需要 Mac App；Mac 安裝版仍使用原本的 USB 配對流程。2026-11-02 已用 SideStore 實機驗證匯入、瞬移、路線背景移動，以及手機重開機後的定位；自動漫步在背景偶爾會被 iOS 暫停。

開發者執行 `bash app/GoFly/scripts/package-ipa.sh` 產生未簽名 IPA 與 SHA-256（須先有 `work/gofly-ios/native` 的已建置原生程式庫）。輸出一律放在 `work/dist/ipa/`；同版本的舊 IPA 與校驗檔會先移到 `work/dist/ipa/archive/<UTC 時間>/`，不會被覆蓋或刪除。腳本不更動 Mac 建置。

## 讓 AI 幫你安裝

把 GitHub 網址連同下面的 prompt 貼給能執行 shell 指令（最好也能操作你的 Mac）的 AI 助理：

```text
請幫我從 https://github.com/nevenhsu/GoFly 安裝 GoFly。

1. 先讀該專案的 README.md 與 docs/AI-INSTALL.md。
2. 不要從原始碼建置。把最新 Release 的 GoFly-<版本>-arm64.dmg 與 .sha256
   下載到一個全新的空資料夾（例如用 `gh release download`），執行
   `shasum -a 256 -c`，結果不是 OK 就停止。
3. 掛載 DMG，在終端機執行 `bash /Volumes/GoFly/install.sh`。不要雙擊、不要用
   sudo、不要關閉 Gatekeeper。出現取代提示時，必須我確認才回答 y。
4. 開啟 GoFly for Mac，帶著我逐步操作。Apple 登入、雙重認證、鑰匙圈密碼提示、
   iPhone 信任、開發者模式、VPN 權限與安裝 LocalDevVPN 由我自己處理。不要要求我把
   密碼、配對檔或 token 貼到聊天裡。
5. 不要卸載任何東西、不要刪除 App 資料。中斷時使用 App 內的「重新開始」，不要自行
   想辦法接續。
6. 回報已完成的項目、我還要在 iPhone 上做的事，以及阻礙。安裝成功不代表模擬定位
   一定可用，請另外說明。
```

給 AI 助理的完整操作說明在 [docs/AI-INSTALL.md](docs/AI-INSTALL.md)。

## 疑難排解

| 症狀 | 處理方式 |
| --- | --- |
| 「Apple 無法驗證 install.sh…」 | 不要雙擊。在終端機執行 `bash /Volumes/GoFly/install.sh`。 |
| `/Volumes/GoFly/install.sh: No such file` | DMG 沒有掛載，或掛著舊的。在 Finder 退出 GoFly，再開啟新的 DMG。 |
| `install.sh` 停在提示不動 | 輸入 `y` **後要按 Enter**。 |
| 找不到 iPhone | 使用資料線、解鎖手機、點「信任」、開啟開發者模式（需重新開機）。 |
| 「無法完成安裝前檢查」 | 按**再檢查一次**。若手機上已有 GoFly，點側欄的裝置，使用 **Renew Signing**。 |
| iPhone 上的 App 打不開 | 簽名已過期。從 Mac App 延長簽名，資料會保留。 |
| LocalDevVPN 已開但 GoFly 無法繼續 | 確認 VPN 實際已連線且已允許，再回 GoFly 重試。 |

## 從原始碼建置

只有開發時需要。在安裝了完整 Xcode 的 Apple Silicon Mac 上：

```sh
bash app/GoFlyMac/make-dmg.sh <你的_XCODE_TEAM_ID>
```

會產生 `work/dist/GoFly-<版本>-arm64.dmg` 與 `.sha256`（不納入版本控制）。詳見 [app/GoFlyMac/README.md](app/GoFlyMac/README.md)、[app/GoFly/README.md](app/GoFly/README.md) 與 [docs/MAC-INSTALLER-SPEC.md](docs/MAC-INSTALLER-SPEC.md)。

## 現況與限制

- 第一版只支援 Apple Silicon Mac；不含 Intel Mac、公證、備份／還原。
- 乾淨 Mac 驗收與長時間實機測試尚未完成；安裝成功不代表每台裝置的背景運行、重新連線或 GPS 還原都正常。請在自己的 iPhone 上測試，並確認事後真實位置已還原。
- 只在你自己擁有的裝置上使用 GoFly，並遵守當地法律與你測試的 App 的服務條款。

## 文件

| 路徑 | 用途 |
| --- | --- |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | 給 AI 助理的安裝操作說明。 |
| [docs/MAC-INSTALLER-SPEC.md](docs/MAC-INSTALLER-SPEC.md) | Mac App 流程與行為。 |
| [docs/IOS-UI-DESIGN.md](docs/IOS-UI-DESIGN.md) | iOS UI 設計與驗收。 |
| [docs/LICENSING.md](docs/LICENSING.md) | 授權與來源。 |

## 授權

新撰寫、獨立擁有的內容（根目錄 README 與 `docs/` 下的指南）採用 **0BSD**，見 [LICENSE](LICENSE)。這不會重新授權既有的 App 程式碼或相依套件。源自 LocalGo/StikDebug 的部分保留 AGPL-3.0 聲明，Mac App 內附 GPL-3.0 的 `pymobiledevice3`，因此合併發行不能說成完全免署名。詳見 [docs/LICENSING.md](docs/LICENSING.md) 與 [app/GoFly/Legal/SOURCES.txt](app/GoFly/Legal/SOURCES.txt)。GoFly 不使用也不散布 AnyGo／iToolab 的程式碼、素材或服務。
