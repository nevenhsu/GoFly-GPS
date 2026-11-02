# GoFly

[English](README.md) · [繁體中文](README.zh-Hant.md) · **简体中文**

GoFly 是一个让你在自己的 iPhone 上选择并移动模拟 GPS 位置的 App。**GoFly for Mac** 使用你在 Xcode 登录的 Apple 账号，通过 USB 安装 iPhone App，并可更新签名，让 App 持续可用。

[**下载最新版 GoFly for Mac（DMG）**](https://github.com/nevenhsu/GoFly/releases/latest)

**开发状态（2026-11-02）：GoFly iOS App 已开发完成。** 可通过 GoFly for Mac 安装，或使用 SideStore／AltStore 安装 IPA。已知限制与尚待验证项目见下方说明。

## iPhone App 的功能

**Light 外观**

<div style="overflow-x: auto; white-space: nowrap;">
  <img src="docs/images/ios/map-teleport.png" alt="地图与瞬移" width="180">&nbsp;&nbsp;<img src="docs/images/ios/routes.png" alt="路线规划" width="180">&nbsp;&nbsp;<img src="docs/images/ios/joystick.png" alt="摇杆与漫步" width="180">
</div>

**Dark 外观**

<div style="overflow-x: auto; white-space: nowrap;">
  <img src="docs/images/ios/map-teleport-dark.png" alt="地图与瞬移" width="180">&nbsp;&nbsp;<img src="docs/images/ios/routes-dark.png" alt="路线规划" width="180">&nbsp;&nbsp;<img src="docs/images/ios/joystick-dark.png" alt="摇杆与漫步" width="180">
</div>

<br>

- **地图与搜索**：搜索地点并跳转过去，界面参考 Google Maps 的版面。
- **瞬移**：把模拟位置移到指定的点，并保持在那里。
- **路线**：在多个点之间规划路线（含道路路线）、保存、导入 GPX，并以步行、自行车、摩托车或汽车的速度执行。
- **摇杆**：用屏幕上的摇杆手动操控移动。
- **漫步**：沿着道路自动行走，可随时手动接管。
- **收藏与已存路线**：保存在手机上，重新签名时数据会保留。
- **状态与恢复**：状态胶囊显示连接状态；App 会自动重新连接，也可手动重试、停止或**还原真实 GPS**。
- **语言**：英文、繁体中文、简体中文。

设备通道使用 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，需另外从 App Store 安装。

## Mac App 的功能

GoFly for Mac 不是定位工具。它用**你的** Xcode 签名 Team 构建 iPhone App、安装到你连接的 iPhone、交付 iPhone App 需要的配对与设备支持，并且要等 iPhone 回报后才显示完成。之后可以通过 USB 或 Wi‑Fi **延长签名**；Mac App 开着时，签名快到期会自动延长。延长签名时 App 内的数据会保留。

## 需求

| 项目 | 需求 |
| --- | --- |
| Mac | Apple Silicon，macOS 15 以上（需符合你 Xcode 的要求）。 |
| Xcode | 从 App Store 安装完整 Xcode 并下载 iOS 平台。全新 Mac 上 GoFly 会逐步引导。 |
| Apple 账号 | 你自己的账号，在 Xcode → Settings → Apple Accounts 登录。免费 Personal Team 即可。GoFly 不会获取你的密码。 |
| iPhone | iOS 26 以上、已解锁；首次安装需 USB 数据线、开启**开发者模式**，并信任这台 Mac。 |
| iPhone App | 已安装 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) 并允许添加 VPN。 |
| 网络 | Apple 签名与地图搜索需要。 |

免费 Personal Team 的签名通常约七天到期；让 Mac App 保持打开会自动延长，也可按 **Renew Signing**。Mac App 显示的到期日在你于自己的设备验证前，仅供参考。

## 安装（DMG）

1. 到[最新版 Release](https://github.com/nevenhsu/GoFly/releases/latest)，把 `GoFly-<版本>-arm64.dmg` 与 `GoFly-<版本>-arm64.dmg.sha256` 下载到同一个文件夹。
2. 核对下载文件，结果必须是 `OK`：

   ```sh
   shasum -a 256 -c GoFly-1.0.0-arm64.dmg.sha256
   ```
3. 打开 DMG，然后**在“终端”运行安装脚本**（macOS 会拦下双击 `install.sh`）：

   ```sh
   bash /Volumes/GoFly/install.sh
   ```

   它只会安装 `/Applications/GoFly.app`，已有旧版时会先询问，并移除该 App 的下载隔离属性后打开。不使用 `sudo`、不改动 Gatekeeper、不动 GoFly 的数据。出现提示时输入 `y` 并按 **Enter**。
4. 在 GoFly for Mac 按画面步骤准备 Xcode，然后用 USB 连接 iPhone、信任这台 Mac、开启开发者模式，按**安装 GoFly**。
5. 在 iPhone 上信任开发者（设置 › 通用 › VPN 与设备管理）、安装并允许 LocalDevVPN，再打开 GoFly。Mac App 读回 iPhone 的确认后才算完成。

这个 App 使用 ad-hoc 签名、**未经公证**，所以不能直接双击打开，请用上面的安装脚本。若你自己拖动 App，请运行 `xattr -dr com.apple.quarantine /Applications/GoFly.app`。

## 用 SideStore 或 AltStore 安装 IPA

不想用 Mac App 时，可以用 [SideStore](https://sidestore.io) 或 [AltStore](https://altstore.io) 以你自己的 Apple ID 重新签名并安装 IPA。两者使用同一份 IPA，第一次打开时要导入这台 iPhone 的配对文件。

**准备**

- iPhone：iOS 26 以上，已打开**开发者模式**。
- 已安装 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) 并允许添加 VPN；使用 GoFly 时连接 Wi‑Fi。
- 一台电脑，用 [iloader](https://github.com/nab138/iloader) 导出这台 iPhone 的配对文件（`pairingFile.plist`）。

**安装**

1. 从[最新版 Release](https://github.com/nevenhsu/GoFly/releases/latest)下载 `GoFly-<版本>.ipa`（可用同名 `.sha256` 核对），传到 iPhone。
2. 选一个侧载工具安装：
   - **SideStore**：按[官方流程](https://docs.sidestore.io/docs/installation/install)完成设置，保持 Wi‑Fi 与 LocalDevVPN 连接，在 **My Apps → ＋** 选这个 IPA。
   - **AltStore**：按 [AltStore 说明](https://faq.altstore.io/)在电脑安装 AltServer、在 iPhone 安装 AltStore，再在 **My Apps → ＋** 选这个 IPA。
3. 免费 Apple ID 的签名约 7 天，请让 SideStore／AltStore 定期刷新；刷新会保留 App 内的数据。

**第一次打开**

1. GoFly 会显示「导入配对文件」。在电脑用 iloader 导出这台 iPhone 的配对文件，传到 iPhone（AirDrop 或「文件」App），点**导入配对文件**选取。
2. 依次允许定位与本地网络，并连接 LocalDevVPN，就可以开始使用。

配对文件必须属于这台 iPhone；其他手机的配对文件会在第一次连接时被拦下。IPA 版不需要 Mac App；Mac 安装版仍使用原来的 USB 配对流程。2026-11-02 已用 SideStore 实机验证导入、瞬移、路线后台移动，以及手机重启后的定位；自动漫步在后台偶尔会被 iOS 暂停。

开发者运行 `bash app/GoFly/scripts/package-ipa.sh` 生成未签名 IPA 与 SHA-256（须先有 `work/gofly-ios/native` 中已构建的原生库）。输出一律放在 `work/dist/ipa/`；同版本的旧 IPA 与校验文件会先移到 `work/dist/ipa/archive/<UTC 时间>/`，不会被覆盖或删除。脚本不修改 Mac 构建。

## 让 AI 帮你安装

把 GitHub 网址连同下面的 prompt 贴给能运行 shell 命令（最好也能操作你的 Mac）的 AI 助手：

```text
请帮我从 https://github.com/nevenhsu/GoFly 安装 GoFly。

1. 先读该项目的 README.md 与 docs/AI-INSTALL.md。
2. 不要从源码构建。把最新 Release 的 GoFly-<版本>-arm64.dmg 与 .sha256
   下载到一个全新的空文件夹（例如用 `gh release download`），运行
   `shasum -a 256 -c`，结果不是 OK 就停止。
3. 挂载 DMG，在终端运行 `bash /Volumes/GoFly/install.sh`。不要双击、不要用
   sudo、不要关闭 Gatekeeper。出现替换提示时，必须我确认才回答 y。
4. 打开 GoFly for Mac，带着我逐步操作。Apple 登录、双重认证、钥匙串密码提示、
   iPhone 信任、开发者模式、VPN 权限与安装 LocalDevVPN 由我自己处理。不要要求我把
   密码、配对文件或 token 贴到聊天里。
5. 不要卸载任何东西、不要删除 App 数据。中断时使用 App 内的“重新开始”，不要自行
   想办法接续。
6. 报告已完成的项目、我还要在 iPhone 上做的事，以及阻碍。安装成功不代表模拟定位
   一定可用，请另外说明。
```

给 AI 助手的完整操作说明在 [docs/AI-INSTALL.md](docs/AI-INSTALL.md)。

## 疑难排解

| 症状 | 处理方式 |
| --- | --- |
| “Apple 无法验证 install.sh…” | 不要双击。在终端运行 `bash /Volumes/GoFly/install.sh`。 |
| `/Volumes/GoFly/install.sh: No such file` | DMG 没有挂载，或挂着旧的。在 Finder 推出 GoFly，再打开新的 DMG。 |
| `install.sh` 停在提示不动 | 输入 `y` **后要按 Enter**。 |
| 找不到 iPhone | 使用数据线、解锁手机、点“信任”、开启开发者模式（需重启）。 |
| “无法完成安装前检查” | 按**再检查一次**。若手机上已有 GoFly，点侧栏的设备，使用 **Renew Signing**。 |
| iPhone 上的 App 打不开 | 签名已过期。从 Mac App 延长签名，数据会保留。 |
| LocalDevVPN 已开但 GoFly 无法继续 | 确认 VPN 实际已连接且已允许，再回 GoFly 重试。 |

## 从源码构建

只有开发时需要。在安装了完整 Xcode 的 Apple Silicon Mac 上：

```sh
bash app/GoFlyMac/make-dmg.sh <你的_XCODE_TEAM_ID>
```

会生成 `work/dist/GoFly-<版本>-arm64.dmg` 与 `.sha256`（不纳入版本控制）。详见 [app/GoFlyMac/README.md](app/GoFlyMac/README.md)、[app/GoFly/README.md](app/GoFly/README.md) 与 [docs/MAC-INSTALLER-SPEC.md](docs/MAC-INSTALLER-SPEC.md)。

## 现状与限制

- 第一版只支持 Apple Silicon Mac；不含 Intel Mac、公证、备份／还原。
- 干净 Mac 验收与长时间真机测试尚未完成；安装成功不代表每台设备的后台运行、重新连接或 GPS 还原都正常。请在自己的 iPhone 上测试，并确认事后真实位置已还原。
- 只在你自己拥有的设备上使用 GoFly，并遵守当地法律与你测试的 App 的服务条款。

## 文档

| 路径 | 用途 |
| --- | --- |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | 给 AI 助手的安装操作说明。 |
| [docs/MAC-INSTALLER-SPEC.md](docs/MAC-INSTALLER-SPEC.md) | Mac App 流程与行为。 |
| [docs/IOS-UI-DESIGN.md](docs/IOS-UI-DESIGN.md) | iOS UI 设计与验收。 |
| [docs/LICENSING.md](docs/LICENSING.md) | 授权与来源。 |

## 授权

新撰写、独立拥有的内容（根目录 README 与 `docs/` 下的指南）采用 **0BSD**，见 [LICENSE](LICENSE)。这不会重新授权既有的 App 代码或依赖。源自 LocalGo/StikDebug 的部分保留 AGPL-3.0 声明，Mac App 内附 GPL-3.0 的 `pymobiledevice3`，因此合并发行不能说成完全免署名。详见 [docs/LICENSING.md](docs/LICENSING.md) 与 [app/GoFly/Legal/SOURCES.txt](app/GoFly/Legal/SOURCES.txt)。GoFly 不使用也不分发 AnyGo／iToolab 的代码、素材或服务。
