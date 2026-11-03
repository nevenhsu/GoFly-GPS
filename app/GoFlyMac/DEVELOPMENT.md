# GoFly for Mac V1 development

Old development trackers and acceptance records were removed on 2026-11-03.
Product behavior is specified by
[`docs/MAC-INSTALLER-SPEC.md`](../../docs/MAC-INSTALLER-SPEC.md); Mac screen
layout and copy follow Figma `05 · Mac Redesign（新版）`.

## App structure

- `Sources/GoFlyMacCore` contains the Mac setup state machine and bridge model.
- `Sources/GoFlyMac` contains Mac-only SwiftUI screens, localization, and
  `MacColorSystem.swift`. Keep Mac semantic color tokens independent from the
  iOS app's color implementation.
- The app bundle contains the pinned Python runtime, bridge, iOS build inputs,
  and native library. Runtime paths are derived from `Bundle.main`.
- macOS appearance follows the system light/dark setting. UI text is localized
  in Traditional Chinese, Simplified Chinese, and English.

## Setup transaction behavior

- A setup journal has one immutable setup ID, device, mode, Team, and pairing
  transaction. `status` reads it without authorizing writes.
- An unfinished operation is shown as D14. “重新開始” creates a new setup ID
  and reruns preflight before apply. A previously installed GoFly uses `renew`
  and preserves the app's user data.
- `apply` archives an older unfinished transaction. If its handoff may have
  published a pairing envelope, the producer atomically renames it out of the
  iOS consumer path, then verifies the exact old pairing transaction ID,
  device ID, pairing bytes, and digest before removing that quarantined file.
  iOS claims an envelope by atomically renaming it to `incoming.plist.consuming`
  before reading or importing; a live claim makes Mac retirement fail closed.
  The active pairing store, activation receipt, app, and other user data remain
  intact. Archived Mac transaction history is reclaimed automatically under the
  retention policy in the installer spec; do not delete it manually. Ambiguous or mismatched envelopes fail closed.
- An unknown write outcome is never replayed using the old setup ID. A new
  explicit apply creates a fresh transaction and a newly generated pairing.
- No setup action connects to or writes a device during offline tests.

## Renewal behavior

- Wi-Fi renew validates and reuses the selected device's existing pairing. It never creates a replacement pairing over Wi-Fi. USB renew follows the explicit pairing handoff path.
- Automatic renewal checks when the app launches and every 24 hours while it stays open. It is per-device, enabled by default, and eligible only below four days of observed signing time, with a usable USB or Wi-Fi route, network access, and no active operation. A failed attempt waits for the next 24-hour check.
- The renewal operation requests a macOS sleep assertion, presents D10, and reports through a macOS notification. The assertion and actual notifications require user-run macOS acceptance; offline tests do not verify OS scheduling behavior.
- Only a verified activation receipt can show a renewed expiry. Otherwise the UI keeps the result pending.

## Bundle, DMG, and colors

- `build-app.sh <TEAM_ID>` creates the local app bundle. The first real build downloads the checksum-pinned CPython archive and installs exact arm64 wheels from `requirements.txt`.
- `make-dmg.sh <TEAM_ID>` ad-hoc signs and verifies the app, creates a versioned arm64 DMG plus SHA-256 file under ignored `work/dist/`, and writes `THIRD-PARTY-NOTICES.md` from bundled wheel metadata. There is no Developer ID signature, notarization, or public release.
- `test-install-quarantine.sh [DMG_PATH]` runs an isolated quarantine simulation in a temporary directory. It does not write to `/Applications` or GoFly user state.
- Mac color tokens are owned by `Sources/GoFlyMac/MacColorSystem.swift`. Views use these semantic Mac-only tokens; they do not import iOS colors.

## Packaging verification

As of 2026-11-03, only IPA/DMG packaging is part of the default workflow.
Offline suites, simulator runs and UI captures require a separate user request.
Packaging retains archive, architecture, dependency and signature checks;
successful packaging is not evidence that tests or device acceptance passed.
Reuse the fixed `work/gofly-ios` and `work/gofly-mac` build paths rather than
creating per-task build or cache directories.

Build a local DMG with the Team ID selected for the bundle identifier:

```sh
bash app/GoFlyMac/make-dmg.sh <TEAM_ID>
```

Offline checks do not replace user-run acceptance on a clean Mac or physical
iPhone. Record observed results and pending items in the relevant current
specification. Do not use offline fixtures
as evidence that an iPhone was installed or that its data was retained.
