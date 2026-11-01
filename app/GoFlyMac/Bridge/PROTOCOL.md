# GoFlyMac Bridge Protocol

`Bridge/bridge.py` handles one request per process. It reads one UTF-8 JSON object from stdin (maximum 32 KiB) and writes one compact response to stdout (maximum 256 KiB). Diagnostics and child process output do not enter the protocol stream.

Every request has UUID `requestID` and `action`. Success replies echo them with `status: "ok"` and a `payload`; failures use `status: "error"` and a stable safe `code`.

## Actions

| Action | Effect |
| --- | --- |
| `environment` | Read-only Mac, Xcode, iOS platform, storage, Apple account and Team observations. Unknown values remain unknown. |
| `devices` | Read-only USB and Network device observations; duplicate transports remain selectable. |
| `inspect` | Read-only inspection of one `deviceID` over the explicit `transport` (`usb` or `wifi`). Lockdown uses `autopair=false`. |
| `registeredDevices` | Read-only list of the phones in one `teamID`'s local Xcode provisioning profiles (`id`, `name` or empty). Names come from `devicectl` when Xcode knows the phone. Never contacts Apple or changes a registration. |
| `preflight` | Read-only validation for one fresh setup transaction. Does not pair, sign, install, or prepare device support. |
| `apply` | Explicitly performs the install or renew transaction after preflight. |
| `status` | Reads the current durable transaction; does not create or repair state. |

`preflight` and `apply` require a UUID `setupID`, normalized `deviceID`, `mode` (`install` or `renew`), and exactly `{ "teamID": "<10-character Team ID>", "allowProvisioningUpdates": <boolean> }` in `options`. `install` requires USB. `renew` accepts USB or Wi-Fi. `inspect` requires an explicit transport and never guesses or silently changes transport. `status` may omit transaction fields to read the global current transaction.

## Bundle paths and state

The app derives resources from `Bundle.main`; no generated setup-configuration JSON, repository path, or workspace fallback is used by the production bundle. The Bridge, CPython interpreter, Python packages, iOS project, and native archive are validated under `Contents/Resources`. Persistent transaction data is private under `~/Library/Application Support/GoFly/state`; old `GoFlySetup` user state is not read, moved, or removed. Python runs isolated with `-I -B` so environment variables and bytecode writes cannot alter the signed app bundle.

## Setup and completion

An install runs `artifact → pairing → install → support → handoff → complete` and refuses an already-installed GoFly. A renew requires the same Team-scoped GoFly app, overwrites it without uninstalling or resetting app data, and completes the same pairing, device-support, and activation-receipt checks.

Wi-Fi renewal validates and reuses the phone's existing pairing; it must not create or deliver a replacement pairing. USB operations use the explicit pairing handoff path. Neither mode is complete until deployment, the required pairing result, device-support observation, and exact activation receipt are confirmed. Missing or unreadable evidence stays pending.

A fresh explicit `apply` archives an unfinished current transaction and starts a new one. Reusing the same setup ID returns `transaction-conflict`. If an old transaction may have published a pairing envelope, the producer atomically quarantines that exact unclaimed envelope and validates its transaction ID, device ID, bytes, and SHA-256 before removing only that object. iOS claims an envelope by renaming it to `incoming.plist.consuming` before reading or importing. A live claim, replacement, or ambiguous state fails closed. The active pairing store, receipt, GoFly app, transaction history, and other user data are retained.

An unknown write outcome is never replayed under the old setup ID. There is no `resume` action: the UI presents D14 and “重新開始,” which begins with a fresh observation and preflight. Offline tests use fake adapters and do not connect to or write a physical iPhone.
