"""Re-sign the saved GoFly IPA with the user's Team (MAC-INSTALLER-SPEC §5.5).

Xcode still owns provisioning: the bundled empty "signing stub" project is built
with the same xcodebuild options as before, which creates or refreshes the
profile and signing certificate for com.neven.gofly.<teamid>. Its profile,
entitlements and certificate are then applied to GoFly.app from the saved IPA.
"""

from __future__ import annotations

import errno
import hashlib
import os
import plistlib
import shutil
import subprocess
from pathlib import Path
from typing import Any

try:
    from .ipa_store import IpaStore
    from .setup_adapters import PinnedXcodeProcessAdapter
    from .setup_protocol import SetupBridgeError, TARGET_NAME, bundle_id_matches_team
except ImportError:  # script execution from the packaged Setup directory
    from ipa_store import IpaStore
    from setup_adapters import PinnedXcodeProcessAdapter
    from setup_protocol import SetupBridgeError, TARGET_NAME, bundle_id_matches_team

CODESIGN = "/usr/bin/codesign"


def _is_no_space_output(output: bytes) -> bool:
    lowered = output.lower()
    return b"no space left on device" in lowered or b"enospc" in lowered or b"not enough space" in lowered


def _run(arguments: list[str], *, timeout: int = 300, code: str = "signing-required") -> bytes:
    try:
        result = subprocess.run(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise SetupBridgeError("timeout") from None
    except OSError as error:
        if getattr(error, "errno", None) == errno.ENOSPC:
            raise SetupBridgeError("ipa-resign-space-insufficient") from None
        raise SetupBridgeError(code) from None
    if result.returncode:
        if _is_no_space_output(result.stdout + result.stderr):
            raise SetupBridgeError("ipa-resign-space-insufficient")
        raise SetupBridgeError(code)
    return result.stdout or result.stderr


def rewrite_info(app: Path, target_bundle_id: str) -> None:
    """Point the payload at the user's bundle ID and require Mac setup."""
    path = app / "Info.plist"
    try:
        info = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError):
        raise SetupBridgeError("ipa-invalid") from None
    if not isinstance(info, dict) or info.get("CFBundleExecutable") != TARGET_NAME:
        raise SetupBridgeError("ipa-invalid")
    base = info.get("CFBundleIdentifier")
    info["CFBundleIdentifier"] = target_bundle_id
    info["GoFlyRequiresMacSetup"] = True
    tasks = info.get("BGTaskSchedulerPermittedIdentifiers")
    if isinstance(tasks, list) and isinstance(base, str):
        info["BGTaskSchedulerPermittedIdentifiers"] = [
            target_bundle_id + item[len(base):] if isinstance(item, str) and item.startswith(base + ".") else item
            for item in tasks
        ]
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))


def signing_identity(stub_app: Path, work: Path) -> str:
    """SHA-1 of the leaf certificate Xcode used, so codesign picks that exact key."""
    prefix = work / "stub-cert"
    _run([CODESIGN, "-d", f"--extract-certificates={prefix}", str(stub_app)], timeout=60)
    leaf = Path(str(prefix) + "0")
    if leaf.is_symlink() or not leaf.is_file():
        raise SetupBridgeError("signing-required")
    return hashlib.sha1(leaf.read_bytes()).hexdigest().upper()


def stub_entitlements(stub_app: Path) -> dict[str, Any]:
    data = _run([CODESIGN, "-d", "--entitlements", ":-", str(stub_app)], timeout=60)
    try:
        value = plistlib.loads(data)
    except (plistlib.InvalidFileException, ValueError):
        raise SetupBridgeError("signing-required") from None
    if not isinstance(value, dict) or "application-identifier" not in value:
        raise SetupBridgeError("signing-required")
    return value


def nested_code(app: Path) -> list[Path]:
    """Frameworks and dylibs, deepest first, so the app is sealed last."""
    found: list[Path] = []
    for path in app.rglob("*"):
        if path.is_symlink():
            raise SetupBridgeError("ipa-invalid")
        if path.suffix == ".framework" and path.is_dir():
            found.append(path)
        elif path.suffix == ".dylib" and path.is_file():
            found.append(path)
    return sorted(found, key=lambda item: len(item.parts), reverse=True)


def resign(app: Path, stub_app: Path, work: Path) -> None:
    for leftover in [app / "embedded.mobileprovision", *app.rglob("_CodeSignature")]:
        if leftover.is_dir():
            shutil.rmtree(leftover)
        elif leftover.exists():
            leftover.unlink()
    profile = stub_app / "embedded.mobileprovision"
    if profile.is_symlink() or not profile.is_file():
        raise SetupBridgeError("signing-required")
    shutil.copyfile(profile, app / "embedded.mobileprovision")
    identity = signing_identity(stub_app, work)
    entitlements = work / "entitlements.plist"
    entitlements.write_bytes(plistlib.dumps(stub_entitlements(stub_app)))
    common = [CODESIGN, "--force", "--sign", identity, "--timestamp=none", "--generate-entitlement-der"]
    for item in nested_code(app):
        _run(common + [str(item)])
    _run(common + ["--entitlements", str(entitlements), str(app)])


class IpaResignProcessAdapter(PinnedXcodeProcessAdapter):
    """Same build() contract as before; the output is the re-signed saved IPA."""

    def build(self, setup_id: str, team_id: str, allow_provisioning_updates: bool = False,
              register_device_id: str | None = None) -> Path:
        target_bundle_id = self.config.target_bundle_id
        if not bundle_id_matches_team(target_bundle_id, team_id):
            raise SetupBridgeError("configuration-invalid")
        store = IpaStore(Path(self.config.state_root))
        saved = store.current()
        if saved is None:
            raise SetupBridgeError("ipa-missing")
        if not saved.get("supported"):
            raise SetupBridgeError("ipa-protocol-unsupported")
        # Xcode creates or refreshes the profile and certificate for this Team.
        built = super().build(setup_id, team_id, allow_provisioning_updates, register_device_id)
        transaction = built.parent
        work = transaction / "resign"
        try:
            if work.exists():
                shutil.rmtree(work)
            work.mkdir(mode=0o700)
            stub_app = work / "stub.app"
            os.rename(built, stub_app)
            app = store.extract_current(transaction, saved["ipaSHA256"])
            rewrite_info(app, target_bundle_id)
            resign(app, stub_app, work)
        except SetupBridgeError:
            raise
        except OSError as error:
            if getattr(error, "errno", None) == errno.ENOSPC:
                raise SetupBridgeError("ipa-resign-space-insufficient") from None
            raise SetupBridgeError("storage-unavailable") from None
        return app
