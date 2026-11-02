# AI installation runbook

Read the [README](../README.md) and applicable workspace rules first. Use the latest [GitHub Release](https://github.com/nevenhsu/GoFly-GPS/releases/latest) for end-user installs; build from source only when requested. If only a repository URL is provided, default to the Mac app route. Follow an explicit request for AltStore or SideStore instead.

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

## Sideload: AltStore or SideStore

Both tools use the same unsigned IPA and the user's Apple ID. This route does not require the GoFly Mac app; pairing is imported on the iPhone.

1. Prepare an iPhone on iOS 26+ with Developer Mode enabled, LocalDevVPN installed, and Wi-Fi available. Use [iloader](https://github.com/nab138/iloader) on a computer to export **this iPhone's** `pairingFile.plist`.
2. Download `GoFly-GPS-<version>.ipa` and its matching `.sha256` from the release. Verify the checksum before transferring the IPA to the phone:

   ```sh
   shasum -a 256 -c GoFly-GPS-<version>.ipa.sha256
   ```

3. Install with the chosen tool:
   - **AltStore:** follow the [AltStore setup guide](https://faq.altstore.io/) to install AltServer on the computer and AltStore on the iPhone, then select the IPA in **My Apps → +**.
   - **SideStore:** follow the [SideStore setup guide](https://docs.sidestore.io/docs/installation/install), keep Wi-Fi and LocalDevVPN connected, then select the IPA in **My Apps → +**.
4. Open GoFly GPS, tap **Import pairing file**, and select the exported file. Allow Location and Local Network access, then connect LocalDevVPN. Another iPhone's pairing file will be rejected at connection.
5. Keep GoFly refreshed through the chosen sideloading tool; free Apple ID signing normally lasts about seven days. Preserve the existing app and its data when refreshing.

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

After an interruption, start with a new preflight/setupID, then apply. The producer archives the single unfinished global transaction; reusing its setupID returns `transaction-conflict`. Do not manually remove journals, pairing data, receipts, or the app. An `incoming.plist.consuming` claim or uncertain replacement must fail closed. Recovery details: [Mac installer spec §5.4](MAC-INSTALLER-SPEC.md).

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
