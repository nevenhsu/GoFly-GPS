# GoFly native bridge

GoFly uses narrow verification-only tunnel and checked location extensions to MIT-licensed idevice by
Jackson Coxson. The Swift module exposes only the functions used by the
production device boundary and audited pairing store. It does not expose
pair-setup, pairing-file generation/write, process-control or JIT APIs.

The upstream `tunnel_create_rppairing` may fall back to pair-setup after failed
verification. The added `tunnel_create_rppairing_verify_only` instead calls
`attempt_pair_verify`, then `validate_pairing`, then the existing TLS/RSD tunnel
completion. A rejected credential is terminal. There is no PIN callback and no
credential update. Output handles are nulled before fallible work and published
only after complete success. Swift still verifies the expected UDID on this
same adapter/handshake before DDI or location operations.

## Location reply boundary

`location-reply.patch` makes the set and clear C exports share a checked void
reply helper. One snapshot of the configured global timeout covers sending,
flushing, waiting and validating; pending request IDs are removed on every
returned outcome. The production Swift queue configures 10 seconds and remains
busy until the actual native call returns. Missing replies, errors, malformed or
unsupported results cannot acknowledge a point, and no point is automatically
resent.

A success requires the same request ID and normalized channel, conversation 1,
no reply request or auxiliary data, and an empty OK or OBJECT nil/NSNull profile.
Raw keyed-archive root/class identity distinguishes nil from an empty dictionary;
the pinned decoder otherwise conflates them. The profiles follow maintained
pymobiledevice3 source at commit `06f3c1c786e11b94c5e20f7d31a3b283f133fa0c`
(`dtx/channel.py`, `dtx/_sender.py`, `dtx/ns_types.py`). An acknowledgement proves
a checked protocol reply, not an observation by a recipient application.

The actual C-export tests use scripted duplex streams for set/clear success,
selector and coordinate arguments, wrong IDs, remote errors, unknown payloads,
channel/conversation mismatches, EOF, blocked sending, silence, unsolicited traffic, and a late
point reply followed by a failing fresh clear. The original source fails the
remote-error rejection test before applying this patch. Four verify-only tunnel
regressions remain part of the same test invocation.

Swift retains the owned location channel after an acknowledged or unconfirmed
set. Revalidation and later points use that same session. Explicit clear releases
it only after native clear returns, even on error; reset refuses an active
session. These lifetimes and the Core dispatch gate were previously checked
by a host Swift 6 harness with session doubles and a timeout setter stub.
That dedicated harness and its runner were removed on 2026-11-03 when the
workflow was reduced to packaging only; those checks are not run by packaging.

## Build

On Apple Silicon with Xcode at `/Applications/Xcode.app`, run from the project:

```sh
app/GoFly/NativeBridge/build.sh
```

The script exports the pinned commit in `upstream.json` from the local research
checkout `work/mac-bootstrap-idevice`. To use another existing clone, set
`GOFLY_IDEVICE_REPOSITORY` to its absolute path; its working tree is never edited.
The pin must exist locally. A fresh clone can be placed under ignored `work/`
from `https://github.com/jkcoxson/idevice.git` before running the script.

Only a fresh archive of that commit is patched. The build-script patch asks
cbindgen to parse the local FFI source tree directly, avoiding its implicit
unlocked `cargo metadata --all-features` dependency fetch. Cargo uses its unchanged lockfile
with `--locked`, disabled default features, and the feature list in the pin.
`dvt` and `location_simulation` are both required: the current remote location
FFI module is gated by both features. Upstream also compiles its legacy location
API under that feature; the Swift shim exposes only the current remote API. No `full`, debug-proxy or JIT
feature is selected. Transitive tunnel/DDI support is included as required.

Rust 1.94.0 standalone components are downloaded from official Rust distribution
URLs and SHA-256 verified against the official release manifest values recorded
in `upstream.json` before their installer scripts run. Toolchain, Cargo home,
Rustup home, dependencies, source export and artifacts stay under ignored
`work/gofly-ios`. No shell profile, system installation or home toolchain changes.
The first build requires public network access for these pinned components and
Cargo's locked dependencies.

## Verification and outputs

The former host Swift harness checked the production error mapper with the
actual service-failure enum, including pair-verify rejection (103/5), timeouts
and operation-specific fallback. That harness is no longer included. The real
iOS branch still imports the shim unconditionally; a missing module fails the
device build.

As of 2026-11-03, `build.sh` only builds and validates the iOS archive for
IPA/DMG packaging. It does not run host regression tests or create host test
products. The generated manifest records native tests as not run.

The retained upstream host Rust regression test sources exercise the actual remote-pairing client and
cryptography against a scripted in-memory peer for successful verification and
rejection. They compare serialized credentials before/after both paths. A
loopback TCP test calls the C export and proves rejection emits only verification
messages, preserves credentials and leaves both output handles null. Rejection codes are asserted as 103/5. Invalid
pointer arguments and malformed address/hostname data also return errors with valid outputs cleared. These tests do
not claim device or end-to-end tunnel acceptance.

The build also compiles C type-compatibility assertions for all 30 shim
declarations, the sizes/alignment/field offsets of both concrete C structs,
and every plist enum value against the newly generated full header. It checks that every
permitted symbol exists in the device archive. This C-only verification never
adds the full header to the production Swift import path.

The device archive is built for `aarch64-apple-ios` with deployment target 26.0.
Generated `work/gofly-ios/native/manifest.json` records the upstream commit,
lockfile, both patches, toolchain, Xcode/SDK, feature selection and archive/header hashes.
`idevice-full.h` is retained there as provenance only. Production Swift imports
only the checked-in `include/idevice.h` shim and `include/module.modulemap`.
Generated artifacts and credentials must never be committed.

This build does not connect to an iOS device, pair, mount DDI, set/clear a device
location, download developer images, or install the application.
