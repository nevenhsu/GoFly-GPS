# AI installation runbook

Read the [README](../README.md) and applicable workspace rules first. Use the current [Mac DMG release](https://github.com/nevenhsu/GoFly-GPS/releases/tag/v1.0.12) or [iOS IPA release](https://github.com/nevenhsu/GoFly-GPS/releases/latest) for end-user installs; build from source only when requested. If only a repository URL is provided, default to the Mac app route. Follow an explicit request for AltStore or SideStore instead.

## Mac app

The Mac app signs and installs GoFly GPS, delivers this iPhone's pairing and required device support, and renews signing while preserving app data.

1. Check the [requirements](../README.md#requirements): Apple Silicon Mac, macOS 15+, full Xcode with an Apple Account, iPhone on iOS 26+, and a USB data cable for first installation.
2. Download `GoFly-GPS-<version>-arm64.dmg` and its matching `.sha256` into an empty folder. Verify the checksum there; stop unless it prints `OK`:

   ```sh
   shasum -a 256 -c GoFly-GPS-<version>-arm64.dmg.sha256
   ```

3. Mount the DMG (eject any older `/Volumes/GoFly` first), then run:

   ```sh
   bash /Volumes/GoFly/install.sh
   ```

   Do not double-click the script, use `sudo`, or disable Gatekeeper. The app is ad-hoc signed and not notarized. The installer asks before replacing `/Applications/GoFly.app`; the user types `y` and presses Enter.
4. Follow the Mac app's setup screens. Verify the intended USB iPhone and signing Team, then install or renew. The user handles Apple sign-in, 2FA, Keychain prompts, device trust, Developer Mode, and developer trust.
5. On the iPhone, install [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), allow VPN setup, and open GoFly GPS. Wait for the Mac app to confirm installation, pairing import, and device preparation.

For an existing app, use renewal without uninstalling. After an interruption, use **Start over**. Mac setup completion does not prove VPN connectivity or location simulation.

## Sideload: SideStore or AltStore (.ipa)

Both tools use the same unsigned IPA and the user's own Apple ID. This route does not require the GoFly Mac app or Xcode; pairing is imported on the iPhone.

### Prerequisites

- iPhone on iOS 26+ with **Developer Mode** enabled (**Settings → Privacy & Security → Developer Mode**, requires a restart).
- [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) installed from the App Store and allowed to add a VPN configuration; Wi-Fi available.
- A computer with [iloader](https://github.com/nab138/iloader/releases/latest), [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases/latest), and a USB data cable.

### SideStore (.ipa) step-by-step

1. **Download and verify the IPA** from the [latest GitHub Release](https://github.com/nevenhsu/GoFly-GPS/releases/latest) into an empty folder. Verify the checksum before transferring the file to the iPhone; stop unless it prints `OK`:

   ```sh
   shasum -a 256 -c GoFly-GPS-<version>.ipa.sha256
   ```

   Transfer the verified `GoFly-GPS-<version>.ipa` to the iPhone (AirDrop, iCloud Drive, or the Files app).

2. **Set up LiveContainer with built-in SideStore (Nightly):**
   - Follow the [README setup](../README.md#set-up-livecontainer-with-built-in-sidestore-nightly) for installation, Remote Pairing with idevice_pair, Anisette, and certificate import. The user enters Apple ID credentials and completes two-factor authentication directly.
   - If the user prefers standalone SideStore, follow the [official SideStore setup guide](https://docs.sidestore.io/docs/installation/install).

3. **Install GoFly GPS in SideStore:**
   - Confirm Wi-Fi and **LocalDevVPN** are connected.
   - In SideStore, go to **My Apps → +** and select `GoFly-GPS-<version>.ipa`.
   - Wait for SideStore to re-sign and install GoFly GPS. Trust the developer profile in iOS Settings if prompted.

4. **First launch of GoFly GPS:**
   - Export this iPhone’s **Remote Pairing** file using idevice_pair and transfer it to the iPhone. You can reuse the Remote Pairing file from the Nightly setup.
   - Connect **LocalDevVPN**, open GoFly GPS, tap **Import pairing file**, and select the exported `.plist` or `.pairfile`. Allow GoFly’s **Local Network** access if prompted and retry if the first check times out. For a file without a UDID, GoFly verifies the local iPhone before saving.
   - Follow the remaining onboarding steps to allow **Location** access and check the VPN connection. Importing a Remote Pairing file without a UDID requires an IPA that includes this change.
   - SideStore does not mount Developer Disk Image (DDI); if GoFly GPS prompts for device support (DDI), follow the in-app download prompt while online.

5. **Keep signing refreshed:**
   - Free Apple ID signing normally lasts about seven days. Keep Wi-Fi and LocalDevVPN connected and refresh SideStore and GoFly GPS in SideStore before expiry. Refreshing preserves existing app data (favorites, saved routes, preferences); do not uninstall.

### Apple ID sign-in errors

For built-in SideStore, follow the [README Anisette sequence](../README.md#configure-anisette-before-signing-in). The maintainer encountered HTTP 403, then HTTP 503. Sync the remote Anisette settings and save them before checking Client Info. For desktop iloader errors, see the separate iloader entry in [README troubleshooting](../README.md#troubleshooting).

### SideStore cannot reach the device (DeviceEndpointNotInitialized)

If installing or refreshing in SideStore shows "Operation Failed … SideStore is unable to reach the device endpoint … `DeviceEndpointNotInitialized`", LocalDevVPN is up but SideStore cannot reach the iPhone through it. **Restart the iPhone**, reconnect Wi‑Fi and **LocalDevVPN**, then retry in SideStore (confirmed on 2026-11-23). Do not delete SideStore or reset the pairing file.

### AltStore (.ipa)

1. Download and verify `GoFly-GPS-<version>.ipa` with its `.sha256` file as above.
2. Follow the [AltStore setup guide](https://faq.altstore.io/) to install AltServer on the computer and AltStore on the iPhone, then select the IPA in **My Apps → +**.
3. Complete the same **First launch of GoFly GPS** and 7-day refresh steps as above.

### Run GoFly GPS inside LiveContainer

1. Follow the [Nightly setup](../README.md#set-up-livecontainer-with-built-in-sidestore-nightly), including importing the signing certificate. Verify the checksum of a GoFly IPA that includes the LiveContainer Local Network fix.
2. Select the IPA in **LiveContainer → Apps → +** and launch GoFly from that Apps list.
3. Connect LocalDevVPN and complete the pairing import and onboarding in GoFly. For permission changes use **Settings → Privacy & Security → Local Network → LiveContainer**. If Files cannot open from GoFly, enable **Fix File Picker** for GoFly in LiveContainer. [LiveContainer installation and compatibility](https://github.com/LiveContainer/LiveContainer#features--guides)
4. For background routes and wandering, hold GoFly GPS in **LiveContainer → Apps**, open **Settings**, and enable **Fix Background Processing Tasks**. Reopen GoFly and start the movement again. [LiveContainer background compatibility](https://github.com/LiveContainer/LiveContainer/issues/1710)
5. Verify that the guest can launch, import this iPhone’s pairing file, pass Local Network and VPN checks, prepare DDI, and reach the map. Treat location simulation and background operation as separate device checks.

This route is pending device validation.

### SideStore IPA AI-install prompt

A user can paste this prompt into an AI assistant to install the release IPA via SideStore:

```text
Help me install GoFly GPS on my iPhone via SideStore from https://github.com/nevenhsu/GoFly-GPS.

1. Read README.md and docs/AI-INSTALL.md in that repository first.
2. Do not build from source. Download the latest release's GoFly-GPS-<version>.ipa
   and its .sha256 file into a new empty folder, run `shasum -a 256 -c`, and stop
   if the result is not OK.
3. Walk me through the README's LiveContainer + SideStore Nightly setup, using
   idevice_pair for Remote Pairing and configuring Anisette before sign-in.
   Then help me install the GoFly GPS IPA via SideStore (My Apps -> +) and import
   this iPhone's Remote Pairing file on first launch of GoFly GPS.
4. If Apple ID sign-in fails, use the README troubleshooting entry for the app
   showing the error (desktop iloader or built-in SideStore).
5. I will handle Apple ID sign-in, 2FA, iPhone trust, Developer Mode, and VPN
   permissions myself. Never ask for passwords, pairing files, or tokens in chat.
6. Report what is completed, what I still need to do on the iPhone, and any
   blocker. Separate installation completion from location simulation verification.
```

Permissions and VPN access alone do not establish pairing or device support. Missing required data must continue to block native positioning. Do not use the Mac producer to prepare a sideloaded Bundle ID or claim AltStore device verification from SideStore results. See the [README](../README.md#install-the-ipa-with-sidestore-or-altstore) for recorded device results.

## Maintainer workflows

These commands are for explicitly requested source builds or device installs, not release-based end-user installation. Do not change version/build numbers unless requested. Reuse `work/gofly-ios` and `work/gofly-mac`; put deliverables and checksums under `work/dist`. Do not automatically run standalone host, UI, or simulator tests or create `.xcresult` bundles.

### Package a sideload IPA

Follow the [iOS build instructions](../app/GoFly/README.md), then run:

```sh
bash app/GoFly/scripts/package-ipa.sh
```

When `work/gofly-ios/native` is missing or was built from a different `upstream.json` or patch set, the packager first runs `app/GoFly/NativeBridge/build.sh`, which fetches the pinned idevice commit into ignored `work/mac-bootstrap-idevice` and downloads the checksum-verified Rust toolchain. It changes `GoFlyRequiresMacSetup` from Boolean `true` to `false` only in the staged Payload; the source and Mac producer stay unchanged. Output is fixed at `work/dist/ipa/`; previous same-version IPA/checksum pairs move to `work/dist/ipa/archive/<UTC time>/`. Verify the final checksum and Payload policy before delivery. Packaging is not device verification.

### Install or renew through the Mac producer

Use `scripts/install-ios-test.sh`, which shares the formal Mac setup producer. Never substitute an install-only Xcode or `devicectl` command.

1. Verify the connected USB iPhone. Read the current Xcode Team using `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`; pass the verified 10-character Team explicitly. If none or several are found, ask the user. Never hardcode or switch Teams to force success.
2. Run read-only preflight, then apply only within the user's installation authorization. Use `install` for first installation and `renew` for an existing app. Include `--allow-provisioning-updates` on **both** commands only when authorized:

   ```sh
   bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team <XCODE_TEAM_ID> --mode renew --action preflight --allow-provisioning-updates
   bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team <XCODE_TEAM_ID> --mode renew --action apply --setup-id <PREFLIGHT_SETUP_ID> --allow-provisioning-updates
   ```

3. Require `complete=true` and `installationConfirmed`, `pairingImported`, and `supportObserved` all `true`, including the exact app activation receipt. Confirm existing preferences, favorites, and routes were retained.

The pinned USB adapter needs `/var/run/usbmuxd`; restricted access can misreport `PermissionError` as `device-disconnected`. Where Codex requires and supports escalation, use `sandbox_permissions: "require_escalated"` from preflight onward. If access is denied, stop and report it; do not use `sudo` or another install path.

Renewal preserves data only for the same Team-scoped Bundle ID. The old `com.neven.gofly` is a separate app with no automatic migration.

After an interruption, start with a new preflight/setupID, then apply. The producer archives the single unfinished global transaction; reusing its setupID returns `transaction-conflict`. Old archived transaction products and histories are reclaimed automatically after a successful setup under the same operation lock: products first, then whole transactions outside both the latest 10 eligible archives and the last 90 days. Existing archives follow the same rules on the next successful setup. Current setup, its Wi-Fi pairing source, each device's latest completed archive, pending handoff files, unrecognized staging at the transaction root, and unknown transaction states are protected. Archived Mac-local `.support.<24-hex>.staging` and `.support.actual.<24-hex>.staging` directories and all staging inside rebuildable product directories are reclaimable. Nested staging in other directories does not by itself block product pruning; unlisted top-level contents still block whole-transaction deletion. `xcodebuild-error.txt` is reclaimed with eligible archived transactions. Symlinks and unexpected types are skipped and recorded. Cleanup failures do not fail installation and are retried at the next successful setup; interrupted `.deleting-*` directories require the durable retention intent, independent of the rotating 1000-line summary log. No phone files, activation receipts, installed apps, or user data are changed by retention. No manual cleanup is needed or allowed: do not manually remove journals, transaction directories, pairing data, receipts, or the app. An `incoming.plist.consuming` claim or uncertain replacement must fail closed. Recovery details: [Mac installer spec §5.4](MAC-INSTALLER-SPEC.md).

### iOS device-test prompt

Reading this prompt does not authorize installation. A user can submit it to authorize a data-preserving update:

```text
In this GoFly workspace, read AGENTS.md and docs/AI-INSTALL.md, then update GoFly on my connected iPhone using scripts/install-ios-test.sh and complete the pairing handoff.

I authorize building, signing, Apple provisioning updates, installation, pairing delivery, and required device preparation. Use renew for an existing app. Verify the USB iPhone and current Xcode Team; ask only if selection is ambiguous. Run preflight, then apply with its setupID and --allow-provisioning-updates on both commands.

Preserve the app and all user data. After an interruption, create a fresh preflight/setupID; do not delete transaction or pairing files. Require complete=true and all three completion proofs. Report the installed version/build, pairing and support results, data preservation, and remaining phone actions. Keep location verification separate. Keep credentials, pairing files, and raw logs private.
```

## Safety and reporting

- The user enters passwords, 2FA codes, and device permissions directly. Never request credentials or pairing files in chat or commit them.
- Do not uninstall, reset data, revoke certificates, or perform destructive recovery without separate authorization. Do not use the retired LocalGo prototype.
- Report the route, version/build, redacted device label, actual writes, completion evidence, and remaining actions or blockers. Distinguish **completed**, **pending user action**, **failed**, and **not verified**.
- Verify VPN, device services, location simulation, and GPS restoration separately when requested. Build success, previews, and installation receipts are not full device acceptance.
