#!/usr/bin/env python3
"""Verify the pinned native patches and the narrow Swift shim."""
import re
from pathlib import Path

app = Path(__file__).resolve().parents[1]
root = app.parents[1]
bridge = app / "NativeBridge"
source = root / "work/gofly-ios/native-source"


def fail(message: str) -> None:
    raise SystemExit(message)


patches = {
    "ffi/src/lib.rs": "gofly_location_reply_tests",
    "ffi/src/dvt/location_simulation.rs": "set_with_timeout",
    "ffi/src/tunnel_provider.rs": ("tunnel_create_rppairing_verify_only", "gofly_pairing_device_udid"),
    "idevice/src/services/dvt/message.rs": "gofly_void_reply",
    "idevice/src/services/dvt/location_simulation.rs": "set_with_timeout",
    "ffi/src/gofly_location_clear.rs": "gofly_coredevice_location_clear",
    "idevice/src/services/core_device/location_service.rs": "clearsimulatedlocation",
}
for relative, marker in patches.items():
    path = source / relative
    markers = (marker,) if isinstance(marker, str) else marker
    if not path.is_file() or not all(name in path.read_text() for name in markers):
        fail(f"Native patch not applied: {relative}")

header = (bridge / "include/idevice.h").read_text()
declarations = set(re.findall(
    r"\b([a-z][a-z0-9_]+)\s*\(", re.sub(r"//[^\n]*", "", header)
))
if len(declarations) != 32 or "gofly_pairing_device_udid" not in declarations:
    fail(f"Swift shim declaration count changed: {len(declarations)}")

project = (app / "GoFly.xcodeproj/project.pbxproj").read_text()
for excluded in ("JITEnableContext.swift", "IdeviceFFIBridge.swift",
                 "DeveloperDiskImageService.swift", "LocalGoMapView.swift"):
    if excluded in project:
        fail("Forbidden prototype source in formal target: " + excluded)

print("PASS: native patches applied and the 32-declaration Swift shim is present.")
