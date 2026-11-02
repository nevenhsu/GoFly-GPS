# AI installation runbook / AI 安裝操作說明 / AI 安装操作说明

[English](#english) · [繁體中文](#繁體中文) · [简体中文](#简体中文)

## Install from a GitHub link (end users) / 從 GitHub 連結安裝

When the user gives only the repository URL (`https://github.com/nevenhsu/GoFly`), install from the **latest GitHub Release**; do not build from source and do not use the maintainer-only scripts below.

1. Download the newest release's `GoFly-<version>-arm64.dmg` and `.sha256` into a new empty folder (`gh release download --repo nevenhsu/GoFly --pattern 'GoFly-*'`, or the release page). Run `shasum -a 256 -c GoFly-<version>-arm64.dmg.sha256`; stop unless it prints `OK`.
2. Mount the DMG (`hdiutil attach <dmg>`; if `/Volumes/GoFly` already exists, eject the old volume first) and run `bash /Volumes/GoFly/install.sh` in Terminal. Never double-click `install.sh`, use `sudo`, or disable Gatekeeper. The script asks before replacing `/Applications/GoFly.app`; the user must type `y` **and press Enter**.
3. Open GoFly for Mac and guide the user through its screens. The user performs Apple sign-in, 2FA, Keychain password prompts, iPhone trust, Developer Mode, the VPN permission and the LocalDevVPN install. Never ask for passwords, pairing files or tokens in chat.
4. Do not uninstall, delete data, or improvise after an interruption; use the app's "Start over". Report completed steps, remaining phone actions and blockers. A completed install is separate from verified location simulation.

使用者只貼 GitHub 網址時，從**最新 GitHub Release** 安裝：下載 DMG 與 `.sha256`、核對 `OK`、在終端機執行 `bash /Volumes/GoFly/install.sh`（不雙擊、不用 sudo、不關 Gatekeeper；取代提示要輸入 `y` 並按 Enter），再帶使用者操作 GoFly for Mac。Apple 登入、雙重認證、鑰匙圈密碼、iPhone 信任、開發者模式、VPN 與 LocalDevVPN 由使用者處理。不要從原始碼建置，也不要使用下方僅限維護者的腳本。

使用者只贴 GitHub 网址时，从**最新 GitHub Release** 安装：下载 DMG 与 `.sha256`、核对 `OK`、在终端运行 `bash /Volumes/GoFly/install.sh`（不双击、不用 sudo、不关 Gatekeeper；替换提示要输入 `y` 并按 Enter），再带用户操作 GoFly for Mac。Apple 登录、双重认证、钥匙串密码、iPhone 信任、开发者模式、VPN 与 LocalDevVPN 由用户处理。不要从源码构建，也不要使用下方仅限维护者的脚本。

## Device-test install/update / 實機測試安裝更新（2026-10-26）

Use the shared entry below for every AI-assisted device test; do not use an install-only Xcode/devicectl command. Existing apps use `renew`, which includes pairing and device preparation. This is an implemented USB development workflow; device success must be recorded separately from offline checks. The pinned `pymobiledevice3` USB adapter must read `/var/run/usbmuxd`; a restricted shell can raise `PermissionError` and misreport `device-disconnected` while Device Hub still shows the iPhone. In Codex, run both preflight and apply with `sandbox_permissions: "require_escalated"` from the outset. Do not first retry in the restricted shell, use `sudo`, or switch install paths; if escalation is rejected, stop and report the blocker.

AI 實機測試固定用以下腳本，與 Mac App 共用正式 producer。`renew` 覆蓋同一 App 並保留偏好、最愛及路線，同時核對並交付該手機的配對資料、準備必要支援；不是移除 App 後重裝。不要以單獨 Xcode／devicectl 安裝取代。Team 不寫死：每次以 `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` 讀取 Xcode 目前登入帳號的 Team ID 並明確指定（Mac App 則使用使用者在畫面選定的 Team）；多個 Team 或讀不到時停止詢問，不自動 fallback；裝置或 Team 身分不符立即停止。目前這條完整交接限 USB。固定 `pymobiledevice3` 需讀取 `/var/run/usbmuxd`；受限命令列的 `PermissionError` 會被 producer 誤報成 `device-disconnected`，即使 Device Hub 看得到手機。Codex 從 `preflight` 起至 `apply` 都要用 `sandbox_permissions: "require_escalated"` 執行；不要先以受限權限重試、改用 `sudo` 或繞過正式流程；升權遭拒時停止回報。

此 maintainer-only 測試腳本依 `--team` 產生 Team 專屬 Bundle ID。舊 `com.neven.gofly` 會成為另一個 App，資料不會自動移轉；`renew` 只會覆蓋相同 Team Bundle ID 的 App 並保留該 App 資料。簽名 Team、描述檔及手機配對仍須逐項核對。

```sh
# After the user authorizes installation and Apple provisioning updates / 使用者授權安裝與 Apple 佈建更新後：
# Codex: invoke both commands with sandbox_permissions="require_escalated"; this is a tool permission, not a shell flag.
bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team <XCODE_TEAM_ID> --mode renew --action preflight --allow-provisioning-updates
bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team <XCODE_TEAM_ID> --mode renew --action apply --setup-id <PREFLIGHT_SETUP_ID> --allow-provisioning-updates
# Interrupted? Do not resume; start over with preflight → apply / 中斷時不接續，從頭重新 preflight → apply
```

Always pass the verified 10-character Team ID explicitly. Never hardcode it: read it from the signed-in Xcode account (`defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`), or use the Team the user picked in the Mac app; if several exist or none is found, stop and ask. First installation uses `--mode install`; an existing app uses `--mode renew`. Provisioning updates are off by default; when the user authorizes them, include `--allow-provisioning-updates` on both preflight and apply. Script success requires `complete=true` and all three proofs, including an exact App activation receipt. Installation alone never counts. No automatic retry, uninstall or data reset. After an interruption, create a new setupID and start with preflight → apply. The producer has one global current transaction: `apply` abandons an unfinished transaction and retains its archived files, then starts fresh. Repeating the identical setupID still returns `transaction-conflict`. iOS claims a pairing envelope by atomically renaming `incoming.plist` to `incoming.plist.consuming` before reading or importing it. Mac restart atomically quarantines an unclaimed envelope, verifies the exact old transaction ID, device ID, pairing bytes, and SHA-256, and removes only that quarantined object. A live claim or replacement fails closed. It does not remove the active pairing store, activation receipt, app, or user data.

首次安裝加 `--mode install`，已有 App 使用 `--mode renew`。簽署 Team 取自 Xcode 目前登入帳號或 Mac App 內使用者選定的 Team，不寫死。預設不連 Apple 更新佈建資料；使用者授權後，`--allow-provisioning-updates` 須同時帶在 preflight 與 apply。三項證據及手機精確啟用回報全部通過才成功；VPN／定位效果仍須另外測試。中斷後建立新的 setupID，從頭重新 preflight → apply；producer 只有一筆全域現行交易，`apply` 會封存任何裝置留下的未完成交易（保留交易資料）並開新交易；相同 setupID 重送仍回 `transaction-conflict`。iOS 先原子 rename `incoming.plist` 為 `incoming.plist.consuming` 再讀取或匯入；Mac restart 將未認領信封原子隔離，再精確核對交易 ID、裝置 ID、配對 bytes 及 SHA-256，只移除隔離檔。iOS claim 或新檔替換時 fail closed；活動配對、activation receipt、App 與其他使用者資料保留。

AI 实机测试同样固定使用此脚本。更新保留偏好、收藏及路线，并核对目标手机的配对资料；中断后使用新的 setupID，从头重新 preflight → apply；全局唯一的未完成交易会在 apply 时封存保留，并开始新交易。iOS 先原子 rename incoming 配对信封为 `.consuming` 再读取；Mac 只会原子隔离、精确验证并移除旧交易的信封。遇到 iOS claim 或新档替换会 fail closed；活动配对、receipt、App 与用户资料保留。不卸载、不清数据。签署 Team 取自 Xcode 当前登录账号或 Mac App 内用户选定的 Team，不写死；用户授权 Apple provisioning 更新后，preflight 和 apply 都带 `--allow-provisioning-updates`。固定 `pymobiledevice3` 需读取 `/var/run/usbmuxd`；受限命令列的 `PermissionError` 会被 producer 误报为 `device-disconnected`。Codex 从 `preflight` 起到 `apply` 都须使用 `sandbox_permissions: "require_escalated"`；不可先以受限权限重试、改用 `sudo` 或绕过正式流程；升权被拒时停止并报告。只有完整安装、配对、设备准备回报全部通过才算完成。

## iOS device-test prompt

### 可直接貼給 AI 的 iPhone 覆蓋安裝 prompt

以下 prompt 供使用者貼上交付任務；僅閱讀本文件不代表要求執行安裝。這裡的「重裝」指保留資料的覆蓋更新，已有 App 使用 `renew`。

```text
請在目前這個 GoFly 專案工作目錄中，使用已驗證的共用安裝流程，將最新 GoFly 覆蓋安裝到我的 iPhone，並完成配對交接。

這次已授權建置、簽署、Apple 佈建資料更新、覆蓋安裝、配對交付及必要裝置準備。請直接執行，不要只提供步驟。

要求：
- 先讀 AGENTS.md 與 docs/AI-INSTALL.md。
- 使用 scripts/install-ios-test.sh；已有 App 使用 --mode renew。
- Codex 執行 preflight 與 apply 都使用 `sandbox_permissions: "require_escalated"`（固定 `pymobiledevice3` 須讀取 `/var/run/usbmuxd`）；受限模式會把 `PermissionError` 誤報為 `device-disconnected`。不得以 `sudo` 或其他安裝路徑繞過。
- 不卸載 App、不清除偏好設定、最愛或路線。
- 核對目前連接的實體 iPhone；若只有一台，直接使用。使用 Xcode 目前登入帳號的 Team（依 AGENTS.md 讀取並明確傳入，不寫死）。
- 先執行 --action preflight，再執行 --action apply。
- preflight 與 apply 都帶 --allow-provisioning-updates，並將 preflight 回傳的同一 setupID 傳給 apply。
- 不得以單獨 Xcode 或 devicectl 安裝取代共用流程。
- 必須確認 complete=true，且 installationConfirmed、pairingImported、supportObserved 全部為 true，才算完成。
- 中斷時建立新的 setupID，從頭重新 preflight → apply；全域唯一未完成交易會在 apply 時封存保留並重新開始，不限該交易的裝置；重送相同 setupID 仍衝突。iOS 先將 `incoming.plist` 原子 rename 為 `.consuming` 才讀取；producer 僅將未認領信封原子隔離，精確驗證後移除該隔離檔。看到 iOS claim 或替換檔時 fail closed，不動活動配對、receipt、App、journal archive 或使用者資料；不要手動刪除這些資料。
- 比對更新前後既有偏好與資料，確認保留。
- 配對資料、憑證與原始日誌只保留在私密／忽略目錄，不貼聊天、不提交。
- 完成後回報手機上的版本/build、配對與裝置準備結果，以及資料保留核對結果。安裝成功與外部地圖定位成功分開說明。
```

## English

The maintainer-only device-test script derives its Bundle ID from `--team`. The old `com.neven.gofly` becomes a separate app and its data is not migrated automatically; `renew` updates only an app with the same Team-scoped Bundle ID and retains that app's data. Team signing, provisioning-profile, and phone-pairing checks still apply.

### Establish the task

1. Read the selected root README, this guide, [Mac capabilities](../app/GoFlyMac/README.md), and applicable workspace rules. Identify whether the user wants a GoFly release or a Mac development-preview run. Continue within existing authorization without asking for the same permission repeatedly.
2. **Current state:** the DMG is published as a GitHub Release (ad-hoc signed, not notarized). Clean-Mac download acceptance and physical iPhone acceptance are still separate and not recorded. Do not invent download URLs, bypass disabled writes, or report preview data as a real install. Do not substitute the retired LocalGo prototype.
3. Check Mac/Xcode, iPhone/iOS, USB, and signing team. Use only the intended phone. Resolve ambiguous device/team selection before writing.
4. The user handles Apple sign-in, passwords, 2FA, terms, Keychain prompts, iPhone trust/Developer Mode, and VPN permission. Do not request credentials or pairing private keys in chat. Report pending physical phone actions.

### Choose the available route

- **GoFly GitHub Release:** verify its official source, version, architecture, minimum OS, and published checksum. For a local build, follow the root README, verify the generated `.sha256` file, then run `bash /Volumes/GoFly/install.sh` in Terminal. The script installs only `/Applications/GoFly.app`, removes quarantine from that app, and opens it. Clean-Mac or other-user download testing remains a user-run task. Do not disable Gatekeeper globally. Then use USB, verify the phone, and use the supported install flow. Verify signing, deployment, pairing import, and required device preparation separately. After verified completion, hand off to LocalDevVPN and GoFly on the phone. A verified VPN channel is distinct from a running location task; service startup must not move the location.
- **Current Mac development app:** use the root README's build/open commands and existing Python environment; the GUI does not install missing dependencies. USB first installation uses formal GoFly, a verified device/team and explicit start. In Codex, run preflight and apply with `sandbox_permissions: "require_escalated"`: the pinned USB adapter needs `/var/run/usbmuxd`, and restricted access is misreported as `device-disconnected`. Apple provisioning updates require the per-operation option and authorization. After an interruption, start over instead of resuming; stop on `transaction-conflict` until the restart path is implemented. Keep preview results separate and honor any user instruction to defer phone operations.
- **LocalGo prototype — retired:** the prototype app and its `localgo_setup.py` install CLI were removed (2026-10-19 and 2026-10-20). GoFly is the only install path; do not attempt the old `com.neven.localgo` flow.

Do not uninstall apps, delete data, revoke certificates, or switch teams to force success. Destructive recovery needs its own authorized scope. An interrupted write may have changed the phone; inspect the same device/transaction before retrying. A completion receipt confirms app/pairing delivery only, not VPN, DDI, or other device services. Verify VPN, service, location simulation, and GPS restoration separately, without presenting this as full GoFly acceptance.

### Report results

Report version/route, redacted device label, preflight, actual writes, installation/pairing/preparation evidence, verified signing expiry, remaining phone actions, and blockers. Distinguish **completed**, **pending user action**, **failed**, and **not verified**. Preview data and old experiments are not current device evidence. Keep pairing files, credentials, signing material, and raw logs out of chat/version control.

## 繁體中文

### 確認任務

1. 先讀選用語言的根目錄 README、本文、[Mac 現況](../app/GoFlyMac/README.md)及適用的工作目錄規則。確認使用者要 GoFly 發行版還是 Mac 開發預覽。沿用已有授權，不重複詢問同一權限。
2. **現況：**DMG 已發布於 GitHub Release（ad-hoc 簽署、未公證）；乾淨 Mac 下載驗收與 iPhone 實機驗收另行記錄，尚未完成。不得捏造下載網址、繞過停用功能、把預覽回報為真實安裝，或改裝已退役的 LocalGo prototype。
3. 檢查 Mac／Xcode、iPhone／iOS、USB 及簽署 Team，只操作指定手機。多裝置／Team 且意圖不明時，寫入前先釐清。
4. Apple 登入、密碼、雙重認證、條款、鑰匙圈提示、手機信任／開發者模式及 VPN 權限由使用者處理。不在聊天索取憑證或配對私鑰；需要實體手機操作時回報待辦。

### 選擇可用路徑

- **GoFly GitHub Release：**核對來源、版本、架構、最低系統與公布校驗碼。若使用本機建置版，依根目錄 README 核對產生的 `.sha256`，再於「終端機」執行 `bash /Volumes/GoFly/install.sh`。腳本只安裝到 `/Applications/GoFly.app`、移除該 App 隔離屬性並開啟它。乾淨 Mac 或另一個帳號下載測試仍由使用者執行。不全域關閉 Gatekeeper。之後以 USB 核對手機並使用正式流程，分別驗證簽署、部署、配對匯入與必要裝置準備。完成驗證後再交接 iPhone LocalDevVPN 與 GoFly；VPN 通道可用不代表定位任務執行中，啟動服務不應移動位置。
- **目前 Mac 開發版：**本機 DMG 已可用 `bash app/GoFlyMac/make-dmg.sh <TEAM_ID>` 建置，來源預覽則用 `bash app/GoFlyMac/build-app.sh <TEAM_ID>`。USB 安裝或 renew 使用正式 GoFly，核對裝置／Team 後明確開始。Codex 的 `preflight` 與 `apply` 都使用 `sandbox_permissions: "require_escalated"`；固定 USB adapter 需要讀取 `/var/run/usbmuxd`，受限存取會被誤報為 `device-disconnected`。Apple 佈建更新須本次選項與授權。中斷後用新 setupID 重新 preflight/apply；同 setupID 衝突時先停止查明。預覽另外標示，並遵守使用者延後手機操作的要求。
- **LocalGo prototype — 已退役：**prototype App 與其 `localgo_setup.py` 安裝 CLI 已分別於 2026-10-19、2026-10-20 移除。GoFly 是唯一安裝路徑，不要再走舊的 `com.neven.localgo` 流程。

不得為了強行成功移除 App、刪資料、撤銷憑證或更換 Team。破壞性修復需要相應授權。寫入中斷可能已改變手機，重試前核對同一裝置／交易。完成回報只證明 App／配對交付，不代表 VPN、DDI 或其他裝置服務。VPN、服務、模擬定位及 GPS 恢復分別驗證，不當作 GoFly 完整驗收。

### 回報結果

回報版本／路徑、遮蔽裝置名稱、預檢、實際寫入項目、安裝／配對／準備證據、已驗證簽名到期日、手機待辦及阻礙。區分「已完成／待使用者操作／失敗／未驗證」；預覽資料與舊實驗不是本次裝置證據。配對檔、憑證、簽署資料及原始日誌不貼聊天、不進版本控制。

## 简体中文

### 确认任务

1. 先读所选语言的根目录 README、本文、[Mac 现状](../app/GoFlyMac/README.md)及适用的工作目录规则。确认用户要 GoFly 发布版还是 Mac 开发预览。沿用已有授权，不重复询问同一权限。
2. **现状：**DMG 已发布于 GitHub Release（ad-hoc 签名、未公证）；干净 Mac 下载验收与 iPhone 真机验收另行记录，尚未完成。不得编造下载网址、绕过禁用功能、把预览报告为真实安装，或改装已退役的 LocalGo prototype。
3. 检查 Mac／Xcode、iPhone／iOS、USB 及签名 Team，只操作指定手机。多设备／Team 且意图不明时，写入前先明确。
4. Apple 登录、密码、双重认证、条款、钥匙串提示、手机信任／开发者模式及 VPN 权限由用户处理。不在聊天索取凭证或配对私钥；需要实体手机操作时报告待办。

### 选择可用路径

- **GoFly GitHub Release：**核对来源、版本、架构、最低系统与公布校验码。本地构建版依根目录 README 核对生成的 `.sha256`，再在“终端”运行 `bash /Volumes/GoFly/install.sh`。脚本只安装到 `/Applications/GoFly.app`、移除该 App 的隔离属性并打开它。干净 Mac 或其他账号下载测试仍由用户执行。不全局关闭 Gatekeeper。之后通过 USB 核对手机并使用正式流程，分别验证签名、部署、配对导入与必要设备准备。完成验证后再交接 iPhone LocalDevVPN 与 GoFly；VPN 通道可用不代表定位任务运行中，启动服务不应移动位置。
- **当前 Mac 开发版：**本地 DMG 可用 `bash app/GoFlyMac/make-dmg.sh <TEAM_ID>` 构建；源码预览使用 `bash app/GoFlyMac/build-app.sh <TEAM_ID>`。USB 首次安装使用正式 GoFly，核对设备／Team 后明确开始。Codex 的 `preflight` 与 `apply` 都使用 `sandbox_permissions: "require_escalated"`；固定 USB adapter 需要读取 `/var/run/usbmuxd`，受限访问会被误报为 `device-disconnected`。Apple 配置更新须本次选项与授权。中断后从头重来、不接续；遇到 `transaction-conflict` 时停止报告。预览另行标注，并遵守用户延后手机操作的要求。
- **LocalGo prototype — 已退役：**prototype App 及其 `localgo_setup.py` 安装 CLI 已分别于 2026-10-19、2026-10-20 移除。GoFly 是唯一安装路径，不要再走旧的 `com.neven.localgo` 流程。

不得为了强行成功移除 App、删数据、撤销证书或更换 Team。破坏性修复需要相应授权。写入中断可能已改变手机，重试前核对同一设备／事务。完成报告只证明 App／配对交付，不代表 VPN、DDI 或其他设备服务。VPN、服务、模拟定位及 GPS 恢复分别验证，不当作 GoFly 完整验收。

### 报告结果

报告版本／路径、脱敏设备名称、预检、实际写入项目、安装／配对／准备证据、已验证签名到期日、手机待办及阻碍。区分“已完成／待用户操作／失败／未验证”；预览数据与旧实验不是本次设备证据。配对文件、凭证、签名资料及原始日志不贴聊天、不进版本控制。

## Shared CLI commands / 共用 CLI 命令 / 共用 CLI 命令

The LocalGo prototype CLI (`LocalGo/MacSetup/localgo_setup.py`) and its tests were removed on 2026-10-20; GoFly is the only install path. The Python environment below is still required because the Mac app's read-only device boundary runs in that pinned environment.

LocalGo prototype CLI（`localgo_setup.py`）與其測試已於 2026-10-20 移除，GoFly 是唯一安裝路徑。下列 Python 環境仍需建立，因為 Mac App 使用剩下的唯讀裝置邊界。

LocalGo prototype CLI（`localgo_setup.py`）及其测试已于 2026-10-20 移除，GoFly 是唯一安装路径。下列 Python 环境仍需创建，因为 Mac App 使用剩下的只读设备边界。

### Python environment / Python 環境 / Python 环境

```sh
python3 -m venv work/mac-setup-env
work/mac-setup-env/bin/python -m pip install -r app/GoFlyMac/requirements.txt
```


## SideStore IPA distribution (2026-11-02)

When explicitly testing the SideStore route, use `bash app/GoFly/scripts/package-ipa.sh` to create `GoFly-<version>.ipa` plus its checksum in `work/dist/ipa/` (the fixed IPA location; do not pass another directory). The source app must be an unsigned iPhoneOS build with Boolean `GoFlyRequiresMacSetup=true`; the packager changes only the staged Payload to Boolean `false`. It does not alter the formal Mac producer or device state. Run `python3 -m unittest discover -s app/GoFly/scripts -p 'test_package_ipa.py'` and verify the final checksum and Payload policy before delivery. An earlier IPA and checksum of the same version are moved to `work/dist/ipa/archive/<UTC time>/` before the new pair is published; nothing is overwritten or deleted.

The user requested deferring the replacement 1.0.4 IPA until pending UI updates are complete. The current `work/dist/GoFly-1.0.4.ipa` remains the original Mac-gated artifact. No new IPA or device verification is claimed by packaging tests. Both install routes use the existing iOS permission/VPN onboarding; those grants do not provision GoFly pairing or support data. Missing data must continue to block native positioning. Mac installation/renew testing still follows the formal producer and its completion proofs above.
