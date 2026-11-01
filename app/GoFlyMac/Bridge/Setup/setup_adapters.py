"""Production-boundary adapters and value types for setup bridge.

The producer never constructs a device dependency at import time.  Tests pass
controlled implementations at these seams; production adapters validate the
pinned dependency and API immediately before their first real call.
"""

from __future__ import annotations

import asyncio
import contextlib
import datetime as dt
import errno
import hashlib
import importlib
import importlib.metadata
import inspect
import json
import os
import plistlib
import re
import subprocess
import stat
import shutil
import tempfile
import threading
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Protocol, Sequence

try:
    from .setup_protocol import (
        SetupBridgeError,
        TARGET_NAME,
        _parse_object,
        _uuid,
        bundle_id_for_team,
        bundle_id_matches_team,
        is_gofly_bundle_id,
        normalized_device,
    )
except ImportError:  # script execution from the packaged Setup directory
    from setup_protocol import SetupBridgeError, TARGET_NAME, _parse_object, _uuid, bundle_id_for_team, bundle_id_matches_team, is_gofly_bundle_id, normalized_device

PMD3_VERSION = "11.31.0"
USB = "USB"
NETWORK = "Network"
WIFI_DEBUGGING_DOMAIN = "com.apple.mobile.wireless_lockdown"
WIFI_DEBUGGING_KEY = "EnableWifiDebugging"
MAX_ARTIFACT_BYTES = 4 * 1024 * 1024 * 1024
MAX_MANIFEST_BYTES = 256 * 1024
MAX_BUILD_BYTES = 128
APP_SETUP_ROOT = "Library/Application Support/GoFlySetup"
READBACK_REQUEST = f"{APP_SETUP_ROOT}/readback-request.json"
READBACK_RESPONSE = f"{APP_SETUP_ROOT}/readback-response.json"
ACTIVATION_RECEIPT = f"{APP_SETUP_ROOT}/activation.json"
FORMAL_INPUT = f"{APP_SETUP_ROOT}/incoming.json"
FORMAL_GENERATIONS = f"{APP_SETUP_ROOT}/generations"
V1_INCOMING = "Library/Application Support/LocalGoSetup/incoming.plist"
V1_INCOMING_CONSUMING = V1_INCOMING + ".consuming"


class _RemoteMissing(Exception):
    """Internal marker for a remote path that is absent."""


def _is_remote_missing(error: BaseException) -> bool:
    return (
        isinstance(error, FileNotFoundError)
        or (
            isinstance(error, OSError)
            and getattr(error, "errno", None) == errno.ENOENT
        )
        or error.__class__.__name__ == "AfcFileNotFoundError"
    )


def _safe_code(value: Any, default: str = "operation-failed") -> str:
    if isinstance(value, TimeoutError):
        return "timeout"
    value = str(getattr(value, "code", value))
    return value if re.fullmatch(r"[a-z][a-z0-9-]{1,80}", value) else default


def _canonical_utc(value: dt.datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


_ASYNC_RUNTIME = threading.local()


def _runtime_loop() -> asyncio.AbstractEventLoop:
    loop = getattr(_ASYNC_RUNTIME, "loop", None)
    if loop is None or loop.is_closed():
        loop = asyncio.new_event_loop()
        _ASYNC_RUNTIME.loop = loop
    return loop


def close_async_runtime() -> None:
    """Close the operation-owned loop after all pmd3 services return."""
    loop = getattr(_ASYNC_RUNTIME, "loop", None)
    if loop is None or loop.is_closed():
        return
    try:
        loop.run_until_complete(asyncio.sleep(0))
    finally:
        loop.close()
        _ASYNC_RUNTIME.loop = None


def _run(value: Any) -> Any:
    if not inspect.isawaitable(value):
        return value
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        # Keep one real loop for the entire bridge operation.  pymobiledevice3
        # Lockdown/RSD services retain loop-bound watchers between calls;
        # asyncio.run would close those watchers after each awaitable.
        return _runtime_loop().run_until_complete(value)
    raise SetupBridgeError("operation-failed")


def _stream_hash(path: Path, *, max_bytes: int = MAX_ARTIFACT_BYTES) -> tuple[int, str]:
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0) | os.O_CLOEXEC,
        )
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size < 0 or info.st_size > max_bytes:
            raise SetupBridgeError("artifact-mismatch")
        digest = hashlib.sha256()
        size = 0
        while size < info.st_size:
            try:
                chunk = os.read(fd, min(1024 * 1024, info.st_size - size))
            except InterruptedError:
                continue
            if not chunk:
                raise SetupBridgeError("artifact-mismatch")
            size += len(chunk)
            if size > max_bytes:
                raise SetupBridgeError("artifact-mismatch")
            digest.update(chunk)
        while True:
            try:
                extra = os.read(fd, 1)
            except InterruptedError:
                continue
            break
        if extra:
            raise SetupBridgeError("artifact-mismatch")
        final = os.fstat(fd)
        if final.st_size != info.st_size or size != info.st_size or not stat.S_ISREG(final.st_mode):
            raise SetupBridgeError("artifact-mismatch")
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("artifact-mismatch") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
    return size, digest.hexdigest()


def _read_regular(path: Path, *, max_bytes: int) -> bytes:
    """Read one regular file through an O_NOFOLLOW descriptor."""
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0) | os.O_CLOEXEC,
        )
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size < 0 or info.st_size > max_bytes:
            raise SetupBridgeError("artifact-mismatch")
        data = bytearray()
        while len(data) < info.st_size:
            try:
                chunk = os.read(fd, min(1024 * 1024, info.st_size - len(data)))
            except InterruptedError:
                continue
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != info.st_size:
            raise SetupBridgeError("artifact-mismatch")
        while True:
            try:
                extra = os.read(fd, 1)
            except InterruptedError:
                continue
            break
        if extra or os.fstat(fd).st_size != info.st_size:
            raise SetupBridgeError("artifact-mismatch")
        return bytes(data)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("artifact-mismatch") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _read_private_regular(path: Path, *, max_bytes: int) -> bytes:
    """Read a transaction-owned 0600, single-link regular file."""
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_NONBLOCK", 0)
            | getattr(os, "O_CLOEXEC", 0),
        )
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_size < 0
            or info.st_size > max_bytes
        ):
            raise SetupBridgeError("storage-unavailable")
        data = bytearray()
        while len(data) < info.st_size:
            try:
                chunk = os.read(fd, min(1024 * 1024, info.st_size - len(data)))
            except InterruptedError:
                continue
            if not chunk:
                raise SetupBridgeError("storage-unavailable")
            data.extend(chunk)
        while True:
            try:
                extra = os.read(fd, 1)
            except InterruptedError:
                continue
            break
        if extra:
            raise SetupBridgeError("storage-unavailable")
        final = os.fstat(fd)
        if (
            not stat.S_ISREG(final.st_mode)
            or final.st_uid != os.getuid()
            or final.st_nlink != 1
            or stat.S_IMODE(final.st_mode) != 0o600
            or final.st_size != info.st_size
        ):
            raise SetupBridgeError("storage-unavailable")
        return bytes(data)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
def _write_private(path: Path, data: bytes) -> None:
    if path.is_symlink() or not path.parent.is_dir():
        raise SetupBridgeError("storage-unavailable")
    if path.exists():
        # Existing private state is never normalized before its owner, link,
        # and mode are checked.  A bad candidate remains a hard failure.
        _read_private_regular(path, max_bytes=max(1, len(data), 1024 * 1024))
    temporary: Path | None = None
    fd: int | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=".candidate-", dir=path.parent)
        temporary = Path(name)
        os.fchmod(fd, 0o600)
        offset = 0
        while offset < len(data):
            written = os.write(fd, data[offset:])
            if written <= 0:
                raise OSError("short candidate write")
            offset += written
        os.fsync(fd)
        os.close(fd)
        fd = None
        if path.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        if path.exists():
            _read_private_regular(path, max_bytes=max(1, len(data), 1024 * 1024))
        os.replace(temporary, path)
        temporary = None
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
        if temporary is not None:
            with contextlib.suppress(OSError):
                temporary.unlink()


def _snapshot_tree(source: Path, destination: Path, *, max_bytes: int = MAX_ARTIFACT_BYTES) -> None:
    """Copy a validated bundle into a private immutable transaction tree."""
    try:
        source_info = source.lstat()
        if not stat.S_ISDIR(source_info.st_mode) or stat.S_ISLNK(source_info.st_mode):
            raise SetupBridgeError("artifact-mismatch")
        destination.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        destination.mkdir(mode=0o700)
        total = 0

        def copy_dir(src: Path, dst: Path) -> None:
            nonlocal total
            for entry in sorted(os.scandir(src), key=lambda item: item.name):
                src_path = Path(entry.path)
                dst_path = dst / entry.name
                info = src_path.lstat()
                if stat.S_ISLNK(info.st_mode):
                    raise SetupBridgeError("artifact-mismatch")
                if stat.S_ISDIR(info.st_mode):
                    dst_path.mkdir(mode=0o700)
                    copy_dir(src_path, dst_path)
                    os.chmod(dst_path, 0o700)
                    continue
                if not stat.S_ISREG(info.st_mode) or info.st_size < 0:
                    raise SetupBridgeError("artifact-mismatch")
                if total + info.st_size > max_bytes:
                    raise SetupBridgeError("artifact-mismatch")
                source_fd = os.open(
                    src_path,
                    os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | getattr(os, "O_NONBLOCK", 0),
                )
                output_fd = os.open(dst_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                try:
                    actual = os.fstat(source_fd)
                    if not stat.S_ISREG(actual.st_mode) or actual.st_size != info.st_size:
                        raise SetupBridgeError("artifact-mismatch")
                    copied = 0
                    while copied < actual.st_size:
                        try:
                            chunk = os.read(source_fd, min(1024 * 1024, actual.st_size - copied))
                        except InterruptedError:
                            continue
                        if not chunk:
                            raise SetupBridgeError("artifact-mismatch")
                        offset = 0
                        while offset < len(chunk):
                            try:
                                written = os.write(output_fd, chunk[offset:])
                            except InterruptedError:
                                continue
                            if written <= 0:
                                raise SetupBridgeError("artifact-mismatch")
                            offset += written
                        copied += len(chunk)
                    final = os.fstat(source_fd)
                    if not stat.S_ISREG(final.st_mode) or final.st_size != actual.st_size:
                        raise SetupBridgeError("artifact-mismatch")
                    os.fchmod(output_fd, info.st_mode & 0o777)
                    os.fsync(output_fd)
                finally:
                    os.close(source_fd)
                    os.close(output_fd)
                total += info.st_size
            directory_fd = os.open(dst, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)

        copy_dir(source, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("artifact-mismatch") from None


def snapshot_artifact(artifact: "ArtifactIdentity", destination: Path, validator: Any, *, device_id: str, team_id: str) -> "ArtifactIdentity":
    """Publish a validated immutable private copy immediately before install."""
    source = Path(artifact.path)
    if not source.exists():
        raise SetupBridgeError("artifact-mismatch")
    destination.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        if destination.is_symlink() or not destination.is_dir():
            raise SetupBridgeError("artifact-mismatch")
        copied = validator.inspect(
            destination, device_id=device_id, team_id=team_id, target_bundle_id=artifact.bundle_id
        )
        if (
            copied.bundle_id != artifact.bundle_id
            or copied.executable != artifact.executable
            or copied.team_id != artifact.team_id
            or copied.artifact_sha256 != artifact.artifact_sha256
            or copied.executable_sha256 != artifact.executable_sha256
            or copied.profile_sha256 != artifact.profile_sha256
            or copied.expires_at != artifact.expires_at
            or copied.build != artifact.build
        ):
            raise SetupBridgeError("artifact-mismatch")
        return ArtifactIdentity(
            str(destination), copied.bundle_id, copied.executable, copied.team_id,
            copied.artifact_sha256, copied.executable_sha256, copied.profile_sha256,
            copied.expires_at, copied.profile, copied.build,
        )
    staging_root = Path(tempfile.mkdtemp(prefix=f".{destination.name}.", dir=destination.parent))
    stage = staging_root / destination.name
    try:
        _snapshot_tree(source, stage)
        copied = validator.inspect(
            stage, device_id=device_id, team_id=team_id, target_bundle_id=artifact.bundle_id
        )
        copied = ArtifactIdentity(
            str(destination), copied.bundle_id, copied.executable, copied.team_id,
            copied.artifact_sha256, copied.executable_sha256, copied.profile_sha256,
            copied.expires_at, copied.profile, copied.build,
        )
        if (
            copied.bundle_id != artifact.bundle_id
            or copied.executable != artifact.executable
            or copied.team_id != artifact.team_id
            or copied.artifact_sha256 != artifact.artifact_sha256
            or copied.executable_sha256 != artifact.executable_sha256
            or copied.profile_sha256 != artifact.profile_sha256
            or copied.expires_at != artifact.expires_at
            or copied.build != artifact.build
        ):
            raise SetupBridgeError("artifact-mismatch")
        directory_fd = os.open(stage.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or not destination.is_dir():
                raise SetupBridgeError("artifact-mismatch")
            existing = validator.inspect(
                destination, device_id=device_id, team_id=team_id, target_bundle_id=artifact.bundle_id
            )
            if (
                existing.bundle_id != artifact.bundle_id
                or existing.executable != artifact.executable
                or existing.team_id != artifact.team_id
                or existing.artifact_sha256 != artifact.artifact_sha256
                or existing.executable_sha256 != artifact.executable_sha256
                or existing.profile_sha256 != artifact.profile_sha256
                or existing.expires_at != artifact.expires_at
                or existing.build != artifact.build
            ):
                raise SetupBridgeError("artifact-mismatch")
            return ArtifactIdentity(
                str(destination), existing.bundle_id, existing.executable, existing.team_id,
                existing.artifact_sha256, existing.executable_sha256, existing.profile_sha256,
                existing.expires_at, existing.profile, existing.build,
            )
        os.rename(stage, destination)
        shutil.rmtree(staging_root, ignore_errors=True)
        stage = Path()
        directory_fd = os.open(destination.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return copied
    finally:
        if stage != Path():
            shutil.rmtree(staging_root, ignore_errors=True)


@dataclass(frozen=True)
class DeviceObservation:
    device_id: str
    os_version: str
    transport: str = "USB"
    developer_mode: bool | None = None
    trust: bool | None = None


@dataclass(frozen=True)
class InstalledAppObservation:
    present: bool
    bundle_id: str = ""
    artifact_sha256: str | None = None
    executable_sha256: str | None = None
    profile_sha256: str | None = None
    setup_nonce: str | None = None
    build: str | None = None


@dataclass(frozen=True)
class ArtifactIdentity:
    path: str
    bundle_id: str
    executable: str
    team_id: str
    artifact_sha256: str
    executable_sha256: str
    profile_sha256: str
    expires_at: str
    profile: Mapping[str, Any] = field(repr=False, compare=False)
    build: str = ""


@dataclass(frozen=True)
class FormalSetupInput:
    """The exact UTF-8 formal manifest frozen before its first upload."""

    raw_manifest: bytes
    sha256: str
    artifacts: tuple[tuple[str, str, int, str], ...]


def build_formal_setup_input(
    *,
    device_id: str,
    setup_id: str,
    nonce: str,
    artifact: ArtifactIdentity,
    pairing_transaction_id: str,
    pairing_sha256: str,
    support: Mapping[str, Any],
) -> FormalSetupInput:
    """Build one deterministic, closed formal input from frozen journal data."""

    try:
        normalized = normalized_device(device_id)
        setup_uuid = uuid.UUID(_uuid(setup_id))
        nonce_value = _uuid(nonce)
        pairing_tx = _uuid(pairing_transaction_id)
        if not isinstance(pairing_sha256, str) or re.fullmatch(r"[0-9a-f]{64}", pairing_sha256) is None:
            raise ValueError()
        if not isinstance(support, Mapping):
            raise ValueError()
        method = support.get("method")
        os_version = support.get("osVersion")
        if method not in {"personalized", "cryptex"} or not isinstance(os_version, str):
            raise ValueError()
        if re.fullmatch(r"(?:26|27)(?:\.\d+){1,2}", os_version) is None:
            raise ValueError()
        parts = [int(part) for part in os_version.split(".")]
        expected_method = "personalized" if parts[0] == 26 and (len(parts) == 1 or parts[1] <= 3) else "cryptex"
        if method != expected_method:
            raise ValueError()
        input_files = support.get("inputFiles")
        input_manifest = support.get("inputManifestSHA256")
        if not isinstance(input_files, Mapping) or not isinstance(input_manifest, str):
            raise ValueError()
        if re.fullmatch(r"[0-9a-f]{64}", input_manifest) is None:
            raise ValueError()
        labels = {
            "MountMethod": "MountMethod",
            "BuildManifest.plist": "manifest",
            "Image.dmg": "image",
            "Image.dmg.trustcache": "trustcache",
        }
        if method == "cryptex":
            labels.update({"Image.dmg.cryptex_info": "cryptex_info", "Image.dmg.root_hash": "root_hash"})
        if set(input_files) != set(labels.values()):
            raise ValueError()
        frozen_files: dict[str, tuple[int, str]] = {}
        for label in labels.values():
            pair = input_files.get(label)
            if not isinstance(pair, (list, tuple)) or len(pair) != 2:
                raise ValueError()
            size, digest = pair
            if type(size) is not int or size <= 0 or size > MAX_ARTIFACT_BYTES:
                raise ValueError()
            if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                raise ValueError()
            frozen_files[label] = (size, digest)
        if frozen_files["manifest"][1] != input_manifest:
            raise ValueError()
        if (
            not bundle_id_matches_team(artifact.bundle_id, artifact.team_id)
            or artifact.executable != TARGET_NAME
            or not re.fullmatch(r"[A-Z0-9]{10}", artifact.team_id)
            or not artifact.build
            or len(artifact.build.encode("utf-8")) > MAX_BUILD_BYTES
            or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", artifact.expires_at)
            or any(re.fullmatch(r"[0-9a-f]{64}", value) is None for value in (
                artifact.profile_sha256, artifact.executable_sha256
            ))
        ):
            raise ValueError()
        names = list(labels)
        records: list[tuple[str, str, int, str]] = []
        for filename in names:
            size, digest = frozen_files[labels[filename]]
            records.append((str(uuid.uuid5(setup_uuid, filename)), filename, size, digest))
        manifest = {
            "version": 1,
            "setupID": _uuid(setup_id),
            "nonce": nonce_value,
            "expectedDeviceUDID": normalized,
            "pairingTransactionID": pairing_tx,
            "pairingSHA256": pairing_sha256,
            "app": {
                "bundleID": artifact.bundle_id,
                "build": artifact.build,
                "profileSHA256": artifact.profile_sha256,
                "executableSHA256": artifact.executable_sha256,
            },
            "teamID": artifact.team_id,
            "signingExpiry": artifact.expires_at,
            "deviceOS": os_version,
            "method": method,
            "artifacts": [
                {"id": item_id, "filename": filename, "byteCount": size, "sha256": digest}
                for item_id, filename, size, digest in records
            ],
        }
        raw = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        if len(raw) > MAX_MANIFEST_BYTES:
            raise ValueError()
        return FormalSetupInput(raw, hashlib.sha256(raw).hexdigest(), tuple(records))
    except SetupBridgeError:
        raise SetupBridgeError("handoff-unknown") from None
    except (AttributeError, TypeError, ValueError, UnicodeError):
        raise SetupBridgeError("handoff-unknown") from None


@dataclass(frozen=True)
class PairingObservation:
    state: str  # absent, invalid, verified
    device_id: str | None = None
    sha256: str | None = None


@dataclass(frozen=True)
class SupportObservation:
    observed: bool
    method: str
    os_version: str
    generation_id: str | None = None
    identifier: str | None = None
    version: str | None = None


@dataclass(frozen=True)
class ReadbackObservation:
    nonce: str
    setup_id: str
    device_id: str
    artifact_sha256: str
    executable_sha256: str
    profile_sha256: str
    pairing_sha256: str
    support_method: str = ""
    support_generation_id: str = ""
    build: str = ""


@dataclass(frozen=True)
class ActivationReceiptObservation:
    """One strict, committed SetupReceipt selected from activation.json."""

    setup_id: str
    nonce: str
    device_id: str
    raw_manifest_sha256: str
    pairing_transaction_id: str
    pairing_sha256: str
    bundle_id: str
    build: str
    profile_sha256: str
    executable_sha256: str
    team_id: str
    signing_expiry: str
    device_os: str
    method: str
    generation_id: str
    artifacts: tuple[tuple[str, int, str], ...]
    # The closed receipt also retains the UUID-bound artifact IDs so the
    # producer can compare the committed inventory with the staged manifest.
    artifact_records: tuple[tuple[str, str, int, str], ...] = ()


class DeviceAdapter(Protocol):
    def observe(self, device_id: str) -> DeviceObservation: ...

    def installed(self, device_id: str) -> InstalledAppObservation: ...

    def pair(self, device_id: str, candidate: Path) -> PairingObservation: ...

    def verify_pairing(self, device_id: str, candidate: Path) -> PairingObservation: ...

    def retire_pending_pairing(self, device_id: str, transaction_id: str) -> None: ...

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation: ...

    def query_support(self, device_id: str, method: str) -> SupportObservation: ...

    def install_support(self, device_id: str, method: str, restore_dir: Path) -> SupportObservation: ...

    def readback(self, device_id: str, setup_id: str, nonce: str) -> ReadbackObservation | None: ...

    def read_activation_receipt(
        self, device_id: str, setup_id: str, nonce: str
    ) -> ActivationReceiptObservation | None: ...

    def launch(self, device_id: str) -> int: ...

    def stop(self, device_id: str, expected_pid: int | None = None) -> None: ...


class ProcessAdapter(Protocol):
    def build(self, setup_id: str, team_id: str, allow_provisioning_updates: bool = False,
              register_device_id: str | None = None) -> Path: ...


class SupportAdapter(Protocol):
    def query(self, device_id: str, method: str) -> SupportObservation: ...

    def install(self, device_id: str, method: str, restore_dir: Path) -> SupportObservation: ...


class PinnedXcodeProcessAdapter:
    """Build the bundled GoFly project from private Application Support copies."""

    def __init__(self, config: Any, *, timeout: int = 900):
        self.config = config
        self.timeout = timeout

    @staticmethod
    def _record_build_errors(transaction_root: Path, output: bytes) -> None:
        """Keep only xcodebuild ``error:`` lines in a private file for diagnosis."""
        try:
            lines = [line for line in output.decode("utf-8", "replace").splitlines() if "error:" in line]
            data = "\n".join(lines[:20])[:8000].encode("utf-8")
            fd = os.open(transaction_root / "xcodebuild-error.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
        except OSError:
            pass

    def build(self, setup_id: str, team_id: str, allow_provisioning_updates: bool = False,
              register_device_id: str | None = None) -> Path:
        try:
            target_bundle_id = self.config.target_bundle_id
            if not bundle_id_matches_team(target_bundle_id, team_id):
                raise SetupBridgeError("configuration-invalid")
            resources_project = self.config.project_path.parent
            build_root = Path(self.config.state_root).parent / "build"
            if build_root.exists() and (build_root.is_symlink() or not build_root.is_dir()):
                raise SetupBridgeError("storage-unavailable")
            build_root.mkdir(parents=False, exist_ok=True, mode=0o700)
            os.chmod(build_root, 0o700)
            project_copy = build_root / "project"
            derived = build_root / "derived"
            for destination in (project_copy, derived):
                if destination.exists():
                    if destination.is_symlink() or not destination.is_dir():
                        raise SetupBridgeError("storage-unavailable")
                    shutil.rmtree(destination)
            for source in resources_project.rglob("*"):
                # SwiftPM keeps a developer build cache here; it may contain
                # symlinks and is not part of the iOS project inputs.
                if ".build" in source.relative_to(resources_project).parts:
                    continue
                if source.is_symlink():
                    raise SetupBridgeError("configuration-invalid")
            shutil.copytree(resources_project, project_copy, ignore=shutil.ignore_patterns(".build"))
            derived.mkdir(mode=0o700)

            transaction = Path(self.config.state_root) / "transactions" / setup_id / "build"
            if transaction.exists() and transaction.is_symlink():
                raise SetupBridgeError("storage-unavailable")
            transaction.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(transaction, 0o700)
            arguments = [
                "/usr/bin/xcodebuild",
                "-project", str(project_copy / "GoFly.xcodeproj"),
                "-scheme", TARGET_NAME,
                "-configuration", "Debug",
                "-sdk", "iphoneos",
                "-derivedDataPath", str(derived),
                "CONFIGURATION_BUILD_DIR=" + str(transaction),
                "GOFLY_NATIVE_DIR=" + str(self.config.resources_root / "native")
                if not self.config.development_mode
                else "GOFLY_NATIVE_DIR=" + str(self.config.resources_root / "work" / "gofly-ios" / "native"),
                "DEVELOPMENT_TEAM=" + team_id,
                "PRODUCT_BUNDLE_IDENTIFIER=" + target_bundle_id,
                "GOFLY_BUNDLE_ID=" + target_bundle_id,
                "CODE_SIGN_STYLE=Automatic",
            ]
            if allow_provisioning_updates:
                arguments.append("-allowProvisioningUpdates")
                # Profile updates alone never add a phone; Xcode registers only
                # a named destination device, so a new phone needs both.
                if register_device_id is not None:
                    arguments += ["-destination", "platform=iOS,id=" + register_device_id.upper(),
                                  "-allowProvisioningDeviceRegistration"]
            environment = os.environ.copy()
            environment["DEVELOPER_DIR"] = str(self.config.developer_directory)
            try:
                result = subprocess.run(
                    arguments,
                    cwd=str(project_copy),
                    env=environment,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=self.timeout,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                raise SetupBridgeError("timeout") from None
            except OSError:
                raise SetupBridgeError("operation-failed") from None
            if result.returncode != 0:
                output = result.stdout + result.stderr
                self._record_build_errors(transaction.parent, output)
                # Apple's per-team phone limit needs the user's action, not a retry.
                if b"maximum number of registered iPhone devices" in output:
                    raise SetupBridgeError("device-limit-reached")
                raise SetupBridgeError("operation-failed")
            output = transaction / f"{TARGET_NAME}.app"
            if output.is_symlink() or not output.is_dir():
                raise SetupBridgeError("artifact-mismatch")
            return output
        except SetupBridgeError:
            raise
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None


FREE_TEAM_SIGNING_DAYS = 7


def xcode_team_is_free(team_id: str) -> bool | None:
    """Read Xcode's own account record: True for a free Personal Team.

    None means the team or the record could not be read.
    """
    try:
        result = subprocess.run(
            ["/usr/bin/defaults", "export", "com.apple.dt.Xcode", "-"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=20, check=False,
        )
        if result.returncode:
            return None
        values = plistlib.loads(result.stdout)
    except Exception:
        return None
    groups = values.get("IDEProvisioningTeamByIdentifier") if isinstance(values, Mapping) else None
    if not isinstance(groups, Mapping):
        return None
    for group in groups.values():
        for item in group if isinstance(group, list) else []:
            if isinstance(item, Mapping) and item.get("teamID") == team_id:
                free = item.get("isFreeProvisioningTeam")
                return free if isinstance(free, bool) else None
    return None


def _signed_time(shown: bytes) -> dt.datetime | None:
    """Parse codesign's local "Signed Time=Nov 1, 2026 at 10:24:18 PM"."""
    match = re.search(rb"^Signed Time=(.+)$", shown, re.MULTILINE)
    if match is None:
        return None
    text = " ".join(match.group(1).decode("utf-8", "replace").split())
    try:
        local = dt.datetime.strptime(text, "%b %d, %Y at %I:%M:%S %p")
    except ValueError:
        return None
    return local.astimezone(dt.timezone.utc)


class FormalArtifactValidator:
    """Validate a GoFly signed artifact without using LocalGo globals."""

    def __init__(self, *, command_runner: Any = None, now: dt.datetime | None = None,
                 team_is_free: Any = None):
        self.command_runner = command_runner or self._run_command
        self.now = now or dt.datetime.now(dt.timezone.utc)
        self.team_is_free = team_is_free

    def signing_expiry(self, profile_expiry: dt.datetime, profile: Mapping[str, Any],
                       shown: bytes, team_id: str) -> dt.datetime:
        """A free Personal Team app lasts 7 days from signing, whatever the
        profile's own date says; a paid team uses the profile date."""
        if self.team_is_free is None or self.team_is_free(team_id) is not True:
            return profile_expiry
        anchor = _signed_time(shown) or profile.get("CreationDate")
        if not isinstance(anchor, dt.datetime):
            return profile_expiry
        if anchor.tzinfo is None:
            anchor = anchor.replace(tzinfo=dt.timezone.utc)
        return min(profile_expiry, anchor + dt.timedelta(days=FREE_TEAM_SIGNING_DAYS))

    @staticmethod
    def _run_command(arguments: Sequence[str], *, timeout: int = 30) -> bytes:
        try:
            result = subprocess.run(
                list(arguments),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise SetupBridgeError("signature-invalid") from None
        if result.returncode:
            raise SetupBridgeError("signature-invalid")
        return result.stdout if result.stdout else result.stderr

    @staticmethod
    def _plist(data: bytes, error: str = "signature-invalid") -> Mapping[str, Any]:
        try:
            value = plistlib.loads(data)
        except Exception:
            raise SetupBridgeError(error) from None
        if not isinstance(value, Mapping):
            raise SetupBridgeError(error)
        return value

    @staticmethod
    def validate_profile(
        info: Mapping[str, Any],
        signed: Mapping[str, Any],
        profile: Mapping[str, Any],
        *,
        device_id: str,
        team_id: str,
        target_bundle_id: str | None = None,
        now: dt.datetime,
    ) -> dt.datetime:
        if target_bundle_id is None:
            target_bundle_id = bundle_id_for_team(team_id)
        if not bundle_id_matches_team(target_bundle_id, team_id):
            raise SetupBridgeError("identity-mismatch")
        expected = f"{team_id}.{target_bundle_id}"
        entitlements = profile.get("Entitlements")
        if not isinstance(entitlements, Mapping):
            raise SetupBridgeError("identity-mismatch")
        if (
            info.get("CFBundleIdentifier") != target_bundle_id
            or info.get("CFBundleExecutable") != TARGET_NAME
            or signed.get("application-identifier") != expected
            or entitlements.get("application-identifier") != expected
            or signed.get("com.apple.developer.team-identifier") != team_id
            or entitlements.get("com.apple.developer.team-identifier") != team_id
            or profile.get("TeamIdentifier") != [team_id]
        ):
            raise SetupBridgeError("identity-mismatch")
        if signed.get("get-task-allow") is not True or entitlements.get("get-task-allow") is not True:
            raise SetupBridgeError("signing-required")
        devices = profile.get("ProvisionedDevices")
        if not isinstance(devices, list) or device_id.lower() not in [str(item).lower() for item in devices]:
            raise SetupBridgeError("identity-mismatch")
        if not isinstance(profile.get("Platform"), list) or "iOS" not in profile["Platform"]:
            raise SetupBridgeError("identity-mismatch")
        expiry = profile.get("ExpirationDate")
        if not isinstance(expiry, dt.datetime):
            raise SetupBridgeError("identity-mismatch")
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=dt.timezone.utc)
        if expiry <= now:
            raise SetupBridgeError("identity-mismatch")
        return expiry

    def inspect(
        self,
        app: str | Path,
        *,
        device_id: str,
        team_id: str,
        target_bundle_id: str | None = None,
    ) -> ArtifactIdentity:
        if target_bundle_id is None:
            target_bundle_id = bundle_id_for_team(team_id)
        if not bundle_id_matches_team(target_bundle_id, team_id):
            raise SetupBridgeError("identity-mismatch")
        path = Path(app)
        if path.is_symlink() or not path.is_dir() or path.suffix != ".app":
            raise SetupBridgeError("artifact-mismatch")
        info_path = path / "Info.plist"
        profile_path = path / "embedded.mobileprovision"
        executable_path: Path
        try:
            info = self._plist(_read_regular(info_path, max_bytes=MAX_MANIFEST_BYTES), "artifact-mismatch")
            executable = info.get("CFBundleExecutable")
            if executable != TARGET_NAME or not isinstance(executable, str):
                raise SetupBridgeError("identity-mismatch")
            executable_path = path / executable
            if executable_path.is_symlink() or not executable_path.is_file():
                raise SetupBridgeError("artifact-mismatch")
            profile_raw = profile_path
            if profile_raw.is_symlink() or not profile_raw.is_file():
                raise SetupBridgeError("artifact-mismatch")
            profile_data = self.command_runner(
                ["/usr/bin/security", "cms", "-D", "-i", str(profile_path)], timeout=30
            )
            profile = self._plist(profile_data)
            signed_data = self.command_runner(
                ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)], timeout=30
            )
            signed = self._plist(signed_data)
            shown = self.command_runner(["/usr/bin/codesign", "-d", "--verbose=4", str(path)], timeout=30)
            if b"Authority=Apple Development:" not in shown or (b"TeamIdentifier=" + team_id.encode()) not in shown:
                raise SetupBridgeError("signing-required")
            self.command_runner(["/usr/bin/codesign", "--verify", "--strict", "-R=anchor apple generic", str(path)], timeout=30)
            expiry = self.validate_profile(
                info, signed, profile, device_id=device_id, team_id=team_id,
                target_bundle_id=target_bundle_id, now=self.now,
            )
            expiry = self.signing_expiry(expiry, profile, shown, team_id)
            executable_size, executable_hash = _stream_hash(executable_path)
            profile_size, profile_hash = _stream_hash(profile_path, max_bytes=MAX_MANIFEST_BYTES)
            artifact_size, artifact_hash = _tree_hash(path)
        except SetupBridgeError:
            raise
        except (OSError, ValueError, TypeError):
            raise SetupBridgeError("artifact-mismatch") from None
        # Keep an explicit size check even though tree hashing streams every file.
        if artifact_size > MAX_ARTIFACT_BYTES or executable_size <= 0 or profile_size <= 0:
            raise SetupBridgeError("artifact-mismatch")
        build = info.get("CFBundleVersion") or info.get("CFBundleShortVersionString")
        if not isinstance(build, str) or not build or len(build.encode("utf-8")) > MAX_BUILD_BYTES:
            raise SetupBridgeError("identity-mismatch")
        return ArtifactIdentity(
            str(path), target_bundle_id, TARGET_NAME, team_id, artifact_hash,
            executable_hash, profile_hash, _canonical_utc(expiry), profile, build,
        )


def _tree_hash(root: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    for path in sorted(root.rglob("*")):
        try:
            info = path.lstat()
        except OSError:
            raise SetupBridgeError("artifact-mismatch") from None
        if stat.S_ISLNK(info.st_mode):
            raise SetupBridgeError("artifact-mismatch")
        if stat.S_ISDIR(info.st_mode):
            continue
        if not stat.S_ISREG(info.st_mode):
            # Devices, FIFOs and sockets must never disappear from the
            # inventory merely because Path.rglob cannot read them.
            raise SetupBridgeError("artifact-mismatch")
        if stat.S_ISREG(info.st_mode):
            relative = path.relative_to(root).as_posix().encode("utf-8")
            remaining = MAX_ARTIFACT_BYTES - total
            if remaining <= 0:
                raise SetupBridgeError("artifact-mismatch")
            size, file_hash = _stream_hash(path, max_bytes=remaining)
            total += size
            digest.update(relative + b"\0" + str(size).encode("ascii") + b"\0" + file_hash.encode("ascii"))
    return total, digest.hexdigest()


class PinnedPymobiledeviceAdapter:
    """USB inspection adapter with explicit 11.31.0 and no autopair."""

    def __init__(
        self,
        *,
        helper_root: Path | None = None,
        state_root: Path | None = None,
        target_bundle_id: str | None = None,
    ):
        self.helper_root = helper_root
        self.state_root = state_root
        self.target_bundle_id = target_bundle_id
        self._modules: tuple[Any, Any, Any] | None = None
        self._process_pids: dict[str, int] = {}
        self._formal_inventories: dict[tuple[str, str], tuple[tuple[str, str, int, str], ...]] = {}

    def _target_bundle_id(self) -> str:
        if not is_gofly_bundle_id(self.target_bundle_id):
            raise SetupBridgeError("configuration-invalid")
        return self.target_bundle_id

    def _load(self) -> tuple[Any, Any, Any]:
        if self._modules is not None:
            return self._modules
        try:
            version = importlib.metadata.version("pymobiledevice3")
            usbmux = importlib.import_module("pymobiledevice3.usbmux")
            lockdown = importlib.import_module("pymobiledevice3.lockdown")
            tunnel = importlib.import_module("pymobiledevice3.remote.tunnel_service")
        except Exception:
            raise SetupBridgeError("dependency-mismatch") from None
        if version != PMD3_VERSION:
            raise SetupBridgeError("dependency-mismatch")
        if not callable(getattr(usbmux, "list_devices", None)) or not callable(getattr(lockdown, "create_using_usbmux", None)):
            raise SetupBridgeError("runtime-api-mismatch")
        self._modules = usbmux, lockdown, tunnel
        return self._modules

    @staticmethod
    def _connection_type(transport: str) -> str:
        if transport == "wifi":
            return NETWORK
        if transport == "usb":
            return USB
        raise SetupBridgeError("invalid-request")

    def transport_serial(self, device_id: str, transport: str = "usb") -> str:
        """Resolve one UDID through exactly the requested usbmux transport."""
        usbmux, _, _ = self._load()
        connection_type = self._connection_type(transport)
        try:
            rows = _run(usbmux.list_devices())
        except Exception:
            raise SetupBridgeError("device-disconnected") from None
        for row in rows if isinstance(rows, list) else []:
            serial = getattr(row, "serial", None) or getattr(row, "udid", None)
            row_transport = getattr(row, "connection_type", None) or getattr(row, "transport", None)
            if (
                isinstance(serial, str)
                and serial.lower() == device_id.lower()
                and isinstance(row_transport, str)
                and row_transport == connection_type
            ):
                return serial
        raise SetupBridgeError("wifi-device-not-found" if transport == "wifi" else "device-disconnected")

    def tunnel_serial(self, device_id: str, transport: str = "usb") -> str:
        """Resolve process-control tunnel serial without allowing an implicit USB fallback."""
        if transport == "usb":
            return self.transport_serial(device_id)
        usbmux, _, _ = self._load()
        try:
            rows = _run(usbmux.list_devices())
        except Exception:
            raise SetupBridgeError("wifi-device-not-found" if transport == "wifi" else "device-disconnected") from None
        selected: str | None = None
        usb_present = False
        for row in rows if isinstance(rows, list) else []:
            serial = getattr(row, "serial", None) or getattr(row, "udid", None)
            kind = getattr(row, "connection_type", None) or getattr(row, "transport", None)
            if not isinstance(serial, str) or serial.lower() != device_id.lower():
                continue
            if kind == USB:
                usb_present = True
            if kind == self._connection_type(transport):
                selected = serial
        if selected is None or (transport == "wifi" and usb_present):
            raise SetupBridgeError("wifi-device-not-found" if transport == "wifi" else "device-disconnected")
        return selected

    def _open(self, serial: str, cache: Path, transport: str = "usb") -> Any:
        _, lockdown, _ = self._load()
        connection_type = self._connection_type(transport)
        transport_serial = self.transport_serial(serial, transport)
        create = lockdown.create_using_usbmux
        client = None
        try:
            client = _run(
                create(
                    serial=transport_serial,
                    label="GoFlyMac Setup",
                    autopair=False,
                    connection_type=connection_type,
                    pair_timeout=60,
                    pairing_records_cache_folder=cache,
                )
            )
            getter = getattr(client, "get_value", None)
            if not callable(getter):
                raise SetupBridgeError("runtime-api-mismatch")
            values = _run(getter())
            if not isinstance(values, Mapping) or str(values.get("UniqueDeviceID", "")).lower() != serial.lower():
                raise SetupBridgeError("identity-mismatch")
            return client
        except SetupBridgeError:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())
            raise
        except Exception as error:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())
            raise SetupBridgeError(_safe_code(error, "trust-required")) from None

    @staticmethod
    def _candidate_pairing_service_class(tunnel: Any, candidate: Path, device_id: str) -> type[Any]:
        """Bind pmd3 remote pairing to one transaction candidate.

        pmd3's service owns a host-wide record cache by default.  The formal
        producer supplies an explicit candidate path and overrides the
        dependency's pair-record load/save hooks, retaining the same host
        identifier through pair and later verify.
        """
        base = getattr(tunnel, "RemotePairingLockdownService", None)
        if base is None:
            raise SetupBridgeError("runtime-api-mismatch")
        adapter = PinnedPymobiledeviceAdapter

        class CandidateRemotePairingLockdownService(base):
            def __init__(self, service: Any, remote_identifier: str, pair_record_path: Path):
                super().__init__(service, remote_identifier)
                self._candidate_record_path = Path(pair_record_path)
                self._pair_record_cache: Mapping[str, Any] | None = None
                if self._candidate_record_path.exists():
                    try:
                        record = plistlib.loads(_read_private_regular(self._candidate_record_path, max_bytes=1024 * 1024))
                        if not isinstance(record, Mapping):
                            raise ValueError()
                        private = record.get("private_key")
                        public = record.get("public_key")
                        identifier = record.get("host_identifier") or record.get("identifier")
                        if not isinstance(private, bytes) or len(private) != 32:
                            raise ValueError()
                        if not isinstance(public, bytes) or len(public) != 32:
                            raise ValueError()
                        if not isinstance(identifier, str):
                            raise ValueError()
                        uuid.UUID(identifier)
                        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

                        if Ed25519PrivateKey.from_private_bytes(private).public_key().public_bytes_raw() != public:
                            raise ValueError()
                        self.ed25519_private_key = Ed25519PrivateKey.from_private_bytes(private)
                        self.identifier = identifier
                        self._pair_record_cache = dict(record)
                    except Exception:
                        raise SetupBridgeError("pairing-unknown") from None
                else:
                    self.identifier = str(uuid.uuid4())

            @classmethod
            async def create(
                cls,
                lockdown_client: Any,
                pair_record_path: Path | None = None,
                *,
                record_path: Path | None = None,
                remote_identifier: str | None = None,
            ) -> Any:
                selected = pair_record_path or record_path
                if selected is None:
                    raise SetupBridgeError("pairing-unknown")
                starter = getattr(lockdown_client, "start_lockdown_service", None)
                if not callable(starter):
                    raise SetupBridgeError("runtime-api-mismatch")
                service_name = getattr(cls, "SERVICE_NAME", "com.apple.dt.remotepairingdeviced.lockdown")
                service = starter(service_name)
                if inspect.isawaitable(service):
                    service = await service
                identifier = remote_identifier or getattr(lockdown_client, "udid", None)
                if not isinstance(identifier, str) or not identifier:
                    raise SetupBridgeError("identity-mismatch")
                return cls(service, identifier, Path(selected))

            @property
            def pair_record_path(self) -> Path:
                return self._candidate_record_path

            @property
            def pair_record(self) -> Mapping[str, Any] | None:
                return self._pair_record_cache

            def save_pair_record(self) -> None:
                data = adapter._pair_record_bytes(self)
                _write_private(self._candidate_record_path, data)
                try:
                    record = plistlib.loads(data)
                except Exception:
                    raise SetupBridgeError("pairing-unknown") from None
                if not isinstance(record, Mapping):
                    raise SetupBridgeError("pairing-unknown")
                self._pair_record_cache = dict(record)

            async def connect(self, autopair: bool = True) -> bool:
                attempt = getattr(self, "_attempt_pair_verify", None)
                validate = getattr(self, "_validate_pairing", None)
                if not callable(attempt) or not callable(validate):
                    raise SetupBridgeError("runtime-api-mismatch")
                await attempt()
                verified = await validate()
                if verified is True:
                    initialize = getattr(self, "_init_client_server_main_encryption_keys", None)
                    if callable(initialize):
                        initialize()
                    return True
                if not autopair:
                    return False
                pair = getattr(self, "_pair", None)
                close = getattr(self, "close", None)
                if not callable(pair) or not callable(close):
                    raise SetupBridgeError("runtime-api-mismatch")
                await pair()
                result = close()
                if inspect.isawaitable(result):
                    await result
                try:
                    completed = getattr(importlib.import_module("pymobiledevice3.exceptions"), "RemotePairingCompletedError")
                except Exception:
                    raise SetupBridgeError("runtime-api-mismatch") from None
                raise completed()

        return CandidateRemotePairingLockdownService

    def observe(self, device_id: str, transport: str = "usb") -> DeviceObservation:
        usbmux, _, _ = self._load()
        connection_type = self._connection_type(transport)
        try:
            rows = _run(usbmux.list_devices())
        except Exception:
            raise SetupBridgeError("wifi-device-not-found" if transport == "wifi" else "device-disconnected") from None
        selected: Any | None = None
        for row in rows if isinstance(rows, list) else []:
            serial = getattr(row, "serial", None) or getattr(row, "udid", None)
            row_transport = getattr(row, "connection_type", None) or getattr(row, "transport", None)
            if (
                isinstance(serial, str)
                and serial.strip().lower() == device_id.lower()
                and row_transport == connection_type
            ):
                selected = row
                break
        if selected is None:
            raise SetupBridgeError("wifi-device-not-found" if transport == "wifi" else "device-disconnected")
        with tempfile.TemporaryDirectory(prefix="gofly-setup-pair-") as directory:
            client = self._open(str(getattr(selected, "serial", device_id)), Path(directory), transport)
            try:
                getter = getattr(client, "get_value", None)
                if not callable(getter):
                    raise SetupBridgeError("runtime-api-mismatch")
                values = _run(getter())
                if not isinstance(values, Mapping):
                    raise SetupBridgeError("identity-mismatch")
                actual = str(values.get("UniqueDeviceID", "")).lower()
                if actual != device_id.lower():
                    raise SetupBridgeError("identity-mismatch")
                version = values.get("ProductVersion")
                if not isinstance(version, str) or not re.fullmatch(r"(?:26|27)\.\d+(?:\.\d+)?", version):
                    raise SetupBridgeError("unsupported-os")
                try:
                    developer_value = _run(getter(domain="com.apple.security.mac.amfi", key="DeveloperModeStatus"))
                except Exception:
                    raise SetupBridgeError("developer-mode-required") from None
                if type(developer_value) is not bool:
                    raise SetupBridgeError("developer-mode-required")
                trusted_value = values.get("TrustedHostAttached")
                if type(trusted_value) is not bool:
                    raise SetupBridgeError("trust-required")
                return DeviceObservation(actual, version, connection_type, developer_value, trusted_value)
            finally:
                with contextlib.suppress(Exception):
                    _run(getattr(client, "close")())

    # Mutating methods deliberately remain explicit call sites.  The
    # orchestrator journals before invoking them and tests inject a controlled
    # implementation, so no accidental hardware call occurs during import.
    def installed(self, device_id: str, transport: str = "usb") -> InstalledAppObservation:
        target_bundle_id = self._target_bundle_id()
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-inspect-") as directory:
                client = self._open(device_id, Path(directory), transport)
                module = importlib.import_module("pymobiledevice3.services.installation_proxy")
                service_cls = getattr(module, "InstallationProxyService", None)
                if service_cls is None:
                    raise SetupBridgeError("runtime-api-mismatch")
                service = service_cls(client)
                apps = _run(service.get_apps(bundle_identifiers=[target_bundle_id]))
                if not isinstance(apps, Mapping):
                    raise SetupBridgeError("runtime-api-mismatch")
                value = apps.get(target_bundle_id)
                if value is None:
                    return InstalledAppObservation(False)
                if not isinstance(value, Mapping):
                    raise SetupBridgeError("runtime-api-mismatch")
                build = value.get("CFBundleVersion")
                return InstalledAppObservation(True, target_bundle_id, build=str(build) if build is not None else None)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("trust-required") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def prepare_pairing(self, device_id: str, candidate: Path) -> None:
        """Enable Wi-Fi debugging and require the actual bool readback.

        This is an explicit mutating boundary.  The producer has already
        persisted pairing=inflight before entering it; a missing setter or a
        non-boolean readback is therefore an unknown pairing result.
        """
        if candidate.is_symlink() or not candidate.parent.is_dir():
            raise SetupBridgeError("storage-unavailable")
        client = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-pair-prepare-") as directory:
                client = self._open(device_id, Path(directory))
                setter = getattr(client, "set_value", None)
                getter = getattr(client, "get_value", None)
                if not callable(setter) or not callable(getter):
                    raise SetupBridgeError("runtime-api-mismatch")
                _run(setter(True, domain=WIFI_DEBUGGING_DOMAIN, key=WIFI_DEBUGGING_KEY))
                value = _run(getter(domain=WIFI_DEBUGGING_DOMAIN, key=WIFI_DEBUGGING_KEY))
                if type(value) is not bool or value is not True:
                    raise SetupBridgeError("pairing-unknown")
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("pairing-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def pair(self, device_id: str, candidate: Path) -> PairingObservation:
        client = None
        service = None
        try:
            _, _, tunnel = self._load()
            with tempfile.TemporaryDirectory(prefix="gofly-setup-pair-") as directory:
                client = self._open(device_id, Path(directory))
                service_cls = self._candidate_pairing_service_class(tunnel, candidate, device_id)
                service = _run(service_cls.create(client, candidate, remote_identifier=device_id))
                try:
                    _run(service.connect(autopair=True))
                except Exception as error:
                    # pmd3 raises this after a successful pair setup.  The
                    # record is still verified below after reopening USB.
                    if error.__class__.__name__ != "RemotePairingCompletedError":
                        raise
                data = _read_private_regular(candidate, max_bytes=1024 * 1024)
                if not data or len(data) > 1024 * 1024:
                    raise SetupBridgeError("pairing-unknown")
                _write_private(candidate, data)
                digest = hashlib.sha256(data).hexdigest()
                return PairingObservation("verified", device_id, digest)
        except SetupBridgeError:
            raise
        except Exception as error:
            raise SetupBridgeError(_safe_code(error, "pairing-unknown")) from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def verify_pairing(self, device_id: str, candidate: Path, transport: str = "usb") -> PairingObservation:
        try:
            try:
                data = _read_private_regular(candidate, max_bytes=1024 * 1024)
            except SetupBridgeError:
                raise SetupBridgeError("pairing-unknown") from None
            if not data:
                raise SetupBridgeError("pairing-unknown")
            value = plistlib.loads(data)
            if not isinstance(value, Mapping):
                raise SetupBridgeError("pairing-unknown")
            required = {"public_key", "private_key", "remote_unlock_host_key", "identifier", "host_identifier"}
            if (
                not required.issubset(value)
                or any(not isinstance(value[key], bytes) for key in ("public_key", "private_key"))
                or not isinstance(value["remote_unlock_host_key"], (str, bytes))
            ):
                raise SetupBridgeError("pairing-unknown")
            if (
                not isinstance(value["identifier"], str)
                or not isinstance(value["host_identifier"], str)
                or value["identifier"] != value["host_identifier"]
            ):
                raise SetupBridgeError("pairing-unknown")
            try:
                uuid.UUID(value["identifier"])
            except (ValueError, AttributeError, TypeError):
                raise SetupBridgeError("pairing-unknown") from None
            # Reopen the selected transport with autopair=False and only accept a verified
            # existing record.  No pair setup or candidate replacement occurs.
            with tempfile.TemporaryDirectory(prefix="gofly-setup-verify-") as directory:
                client = self._open(device_id, Path(directory), transport)
                try:
                    _, _, tunnel = self._load()
                    service_cls = self._candidate_pairing_service_class(tunnel, candidate, device_id)
                    service = _run(service_cls.create(client, candidate, remote_identifier=device_id))
                    try:
                        verified = _run(service.connect(autopair=False))
                        if verified is False:
                            raise SetupBridgeError("pairing-unknown")
                    finally:
                        with contextlib.suppress(Exception):
                            _run(service.close())
                finally:
                    with contextlib.suppress(Exception):
                        _run(client.close())
            return PairingObservation("verified", device_id, hashlib.sha256(data).hexdigest())
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("pairing-unknown") from None

    @staticmethod
    def _pair_record_bytes(service: Any) -> bytes:
        """Serialize the just-established record without reading global cache."""
        try:
            private = service.ed25519_private_key.private_bytes_raw()
            public = service.ed25519_private_key.public_key().public_bytes_raw()
            remote = getattr(service, "remote_unlock_host_key", b"")
            # pmd3 retains the peer's hostKey as a string (including its
            # empty-string fallback). Preserve its plist type; bytes(str)
            # raises after peer-side pairing, before the candidate is saved.
            if not isinstance(remote, (str, bytes)):
                raise ValueError("invalid remote unlock key")
            identifier = str(getattr(service, "identifier", ""))
            uuid.UUID(identifier)
            if len(public) != 32 or len(private) != 32:
                raise ValueError("invalid ed25519 key")
            value: dict[str, Any] = {
                "public_key": public,
                "private_key": private,
                "remote_unlock_host_key": remote,
            }
            # The device binds pair-verify signatures to the host identifier
            # established during pair-setup. Retain it with the candidate so
            # pair verification never falls back to a new random ID.
            value["identifier"] = identifier
            value["host_identifier"] = identifier
            alt = getattr(service, "peer_alt_irk", None)
            if isinstance(alt, bytes):
                value["peer_alt_irk"] = alt
            return plistlib.dumps(value)
        except Exception:
            raise SetupBridgeError("pairing-unknown") from None

    def install(
        self, device_id: str, artifact: ArtifactIdentity, transport: str = "usb"
    ) -> InstalledAppObservation:
        client = None
        service = None
        try:
            # Reinspect the transaction-private immutable artifact before any
            # device client is opened.  The producer has already validated it;
            # this adapter boundary independently closes the source TOCTOU.
            current = FormalArtifactValidator(team_is_free=xcode_team_is_free).inspect(
                artifact.path, device_id=device_id, team_id=artifact.team_id,
                target_bundle_id=artifact.bundle_id,
            )
            if current != artifact:
                raise SetupBridgeError("artifact-mismatch")
            with tempfile.TemporaryDirectory(prefix="gofly-setup-install-") as directory:
                client = self._open(device_id, Path(directory), transport)
                module = importlib.import_module("pymobiledevice3.services.installation_proxy")
                service_cls = getattr(module, "InstallationProxyService", None)
                if service_cls is None:
                    raise SetupBridgeError("runtime-api-mismatch")
                service = service_cls(client)
                _run(service.install_from_local(Path(artifact.path), developer=True))
                # InstallationProxy's successful install return is the
                # transaction-owned result.  Confirm the target lookup and
                # build before publishing that ownership to the journal; the
                # later nonce readback remains a separate app-identity proof.
                apps = _run(service.get_apps(bundle_identifiers=[artifact.bundle_id]))
                value = apps.get(artifact.bundle_id) if isinstance(apps, Mapping) else None
                if not isinstance(value, Mapping):
                    raise SetupBridgeError("commit-unknown")
                remote_build = value.get("CFBundleVersion") or value.get("CFBundleShortVersionString")
                if not isinstance(remote_build, str) or remote_build != artifact.build:
                    raise SetupBridgeError("artifact-mismatch")
                return InstalledAppObservation(True, artifact.bundle_id, build=remote_build)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("operation-failed") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def prepare_readback(
        self,
        device_id: str,
        setup_id: str,
        nonce: str,
        artifact: ArtifactIdentity,
    ) -> None:
        """Publish one immutable App readback request through HouseArrest.

        The request is staged and read back before the remote rename.  A
        same request is retained byte-for-byte. A different request requires
        archiving the exact controls of a fully committed active handoff.
        """

        request = {
            "version": 1,
            "setupID": _uuid(setup_id),
            "nonce": _uuid(nonce),
            "expectedDeviceUDID": normalized_device(device_id),
            "app": {
                "bundleID": artifact.bundle_id,
                "build": artifact.build,
                "profileSHA256": artifact.profile_sha256,
                "executableSHA256": artifact.executable_sha256,
            },
        }
        try:
            data = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        except (TypeError, ValueError, UnicodeError):
            raise SetupBridgeError("handoff-unknown") from None
        if len(data) > 64 * 1024:
            raise SetupBridgeError("handoff-unknown")

        client = None
        service = None
        temporary = f"{APP_SETUP_ROOT}/.readback-{nonce}.staging"
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-readback-") as directory:
                client = self._open(device_id, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, artifact.bundle_id, documents_only=False))
                _run(service.makedirs(APP_SETUP_ROOT))
                if self._remote_exists(service, READBACK_REQUEST):
                    existing = self._read_remote_bounded(service, READBACK_REQUEST)
                    if existing == data:
                        return
                self._retire_completed_controls(service, device_id=device_id)
                if self._remote_exists(service, temporary):
                    raise SetupBridgeError("transaction-conflict")
                _run(service.set_file_contents(temporary, data))
                staged = self._read_remote_bounded(service, temporary)
                if staged != data:
                    raise SetupBridgeError("handoff-unknown")
                _run(service.rename(temporary, READBACK_REQUEST))
                published = self._read_remote_bounded(service, READBACK_REQUEST)
                if published != data:
                    raise SetupBridgeError("handoff-unknown")
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.rm_single(temporary, force=True))
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def _retire_completed_controls(self, service: Any, *, device_id: str) -> None:
        """Archive the previous handshake controls so a fresh request can be published.

        A complete active handshake is archived under its own setup/nonce. Leftovers of
        an abandoned or interrupted transaction (a partial set, or a set that is not the
        active receipt's) are moved, never deleted, into ``retired/abandoned-*`` and the
        handoff continues with new controls.  Activation, support generations, pairing
        and user data are never touched; a pending pairing envelope or any staging file
        still fails closed.
        """
        paths = (READBACK_REQUEST, READBACK_RESPONSE, FORMAL_INPUT)
        present = [self._remote_exists(service, path) for path in paths]
        if not any(present):
            # The previous controls are already archived (or none exist): the activation
            # receipt stays as the active record until a new handoff commits.
            return
        if self._remote_exists(service, V1_INCOMING):
            raise SetupBridgeError("transaction-unknown")
        names = _run(service.listdir(APP_SETUP_ROOT))
        if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
            raise SetupBridgeError("handoff-unknown")
        if any(name.endswith(".staging") for name in names):
            raise SetupBridgeError("transaction-unknown")
        if not all(present):
            self._archive_abandoned_controls(service, [path for path, here in zip(paths, present) if here])
            return
        snapshots = {path: self._read_remote_bounded(service, path, max_bytes=MAX_MANIFEST_BYTES) for path in paths}
        request = _parse_object(snapshots[READBACK_REQUEST], limit=64 * 1024)
        if set(request) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app"} or type(request.get("version")) is not int or request["version"] != 1:
            raise SetupBridgeError("transaction-conflict")
        old_id, old_nonce = _uuid(request.get("setupID")), _uuid(request.get("nonce"))
        active_raw = self._read_remote_bounded(service, ACTIVATION_RECEIPT, max_bytes=MAX_MANIFEST_BYTES)
        active = _parse_object(active_raw, limit=MAX_MANIFEST_BYTES)
        if _uuid(active.get("activeSetupID")) != old_id:
            # Not the committed active handshake: leftovers of an abandoned transaction.
            self._archive_abandoned_controls(service, list(paths))
            return
        receipt = self._decode_activation_receipt(active_raw, device_id=device_id, setup_id=old_id, nonce=old_nonce)
        formal = self._decode_formal_manifest(snapshots[FORMAL_INPUT], device_id=device_id, setup_id=old_id, nonce=old_nonce)
        self._decode_readback(snapshots[READBACK_RESPONSE], device_id=device_id, setup_id=old_id,
                              nonce=old_nonce, target_bundle_id=self._target_bundle_id())
        response = _parse_object(snapshots[READBACK_RESPONSE], limit=64 * 1024)
        active_entry = next(item for item in active["receipts"] if _uuid(item["setupID"]) == old_id)
        if (normalized_device(request["expectedDeviceUDID"]) != normalized_device(device_id)
                or request["app"] != formal["app"] or response["app"] != request["app"]
                or hashlib.sha256(snapshots[FORMAL_INPUT]).hexdigest() != receipt.raw_manifest_sha256
                or any(active_entry.get(key) != value for key, value in formal.items())):
            raise SetupBridgeError("transaction-conflict")
        parent = f"{APP_SETUP_ROOT}/retired"
        try:
            info = _run(service.stat(parent))
        except Exception as error:
            if not _is_remote_missing(error):
                raise SetupBridgeError("handoff-unknown") from None
            _run(service.makedirs(parent))
            info = _run(service.stat(parent))
        if not isinstance(info, Mapping) or info.get("st_ifmt") != "S_IFDIR":
            raise SetupBridgeError("storage-unavailable")
        archive = f"{parent}/{old_id}-{old_nonce}"
        try:
            _run(service.stat(archive))
        except Exception as error:
            if not _is_remote_missing(error):
                raise SetupBridgeError("handoff-unknown") from None
        else:
            # An earlier attempt already owns this archive name: move the controls aside
            # as abandoned instead of mixing them into it.
            self._archive_abandoned_controls(service, list(paths))
            return
        _run(service.makedirs(archive))
        try:
            for path in paths:
                if self._read_remote_bounded(service, path, max_bytes=MAX_MANIFEST_BYTES) != snapshots[path]:
                    raise SetupBridgeError("transaction-unknown")
                destination = f"{archive}/{path.rsplit('/', 1)[1]}"
                _run(service.rename(path, destination))
                if self._read_remote_bounded(service, destination, max_bytes=MAX_MANIFEST_BYTES) != snapshots[path] or self._remote_exists(service, path):
                    raise SetupBridgeError("transaction-unknown")
        except Exception:
            # Do not continue a partial remote multi-file archive on retry.
            raise SetupBridgeError("transaction-unknown") from None

    def _archive_abandoned_controls(self, service: Any, present_paths: list[str]) -> None:
        """Move leftover controls of an abandoned transaction aside; nothing is deleted."""
        parent = f"{APP_SETUP_ROOT}/retired"
        try:
            info = _run(service.stat(parent))
        except Exception as error:
            if not _is_remote_missing(error):
                raise SetupBridgeError("handoff-unknown") from None
            _run(service.makedirs(parent))
            info = _run(service.stat(parent))
        if not isinstance(info, Mapping) or info.get("st_ifmt") != "S_IFDIR":
            raise SetupBridgeError("storage-unavailable")
        archive = f"{parent}/abandoned-{uuid.uuid4()}"
        _run(service.makedirs(archive))
        try:
            for path in present_paths:
                snapshot = self._read_remote_bounded(service, path, max_bytes=MAX_MANIFEST_BYTES)
                destination = f"{archive}/{path.rsplit('/', 1)[1]}"
                _run(service.rename(path, destination))
                if (self._read_remote_bounded(service, destination, max_bytes=MAX_MANIFEST_BYTES) != snapshot
                        or self._remote_exists(service, path)):
                    raise SetupBridgeError("transaction-unknown")
        except Exception:
            raise SetupBridgeError("transaction-unknown") from None

    def deliver_pairing(self, device_id: str, setup_id: str) -> None:
        """Publish the one-shot LocalGo v1 envelope through VendContainer."""
        if self.state_root is None:
            raise SetupBridgeError("configuration-invalid")
        try:
            from .setup_journal import JournalStore
        except ImportError:
            from setup_journal import JournalStore
        journal = JournalStore(self.state_root).read()
        if not isinstance(journal, Mapping) or journal.get("setupID") != _uuid(setup_id):
            raise SetupBridgeError("transaction-conflict")
        pairing = journal.get("pairing", {})
        candidate = self.state_root / "transactions" / _uuid(setup_id) / "pairing.candidate"
        try:
            raw = _read_private_regular(candidate, max_bytes=1024 * 1024)
        except SetupBridgeError:
            raise SetupBridgeError("pairing-unknown") from None
        expected_sha = pairing.get("sha256")
        if not isinstance(expected_sha, str) or hashlib.sha256(raw).hexdigest() != expected_sha:
            raise SetupBridgeError("pairing-unknown")
        transaction_id = journal.get("intent", {}).get("pairingTransactionID")
        if not isinstance(transaction_id, str):
            raise SetupBridgeError("pairing-unknown")
        payload = plistlib.dumps(
            {
                "version": 1,
                "transactionID": transaction_id,
                "expectedDeviceUDID": normalized_device(device_id),
                "pairingFile": raw,
                "sha256": hashlib.sha256(raw).digest(),
            },
            fmt=plistlib.FMT_BINARY,
        )
        if len(payload) > 1 * 1024 * 1024 + 64 * 1024:
            raise SetupBridgeError("pairing-unknown")
        self._publish_house_arrest(device_id, V1_INCOMING, payload, conflict_code="handoff-unknown")

    def retire_pending_pairing(self, device_id: str, transaction_id: str) -> None:
        """Remove only the exact unconsumed one-shot envelope from an older transaction.

        The iOS active PairingFileStore, activation receipts, GoFly app, and all
        other application data remain untouched.
        """
        if not isinstance(transaction_id, str):
            raise SetupBridgeError("transaction-conflict")
        try:
            expected_transaction = str(uuid.UUID(transaction_id)).lower()
        except (ValueError, AttributeError, TypeError):
            raise SetupBridgeError("transaction-conflict") from None
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-retire-pairing-") as directory:
                client = self._open(device_id, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, self._target_bundle_id(), documents_only=False))
                self._retire_pending_pairing_on_service(
                    service, device_id=device_id, transaction_id=expected_transaction
                )
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    @staticmethod
    def _retire_pending_pairing_on_service(service: Any, *, device_id: str, transaction_id: str) -> None:
        staging = V1_INCOMING + ".staging"
        consuming = V1_INCOMING_CONSUMING
        retiring = V1_INCOMING + ".retiring-" + transaction_id
        if PinnedPymobiledeviceAdapter._remote_exists(service, staging):
            raise SetupBridgeError("transaction-unknown")
        if PinnedPymobiledeviceAdapter._remote_exists(service, consuming):
            # iOS atomically claims the envelope before reading or importing
            # it. Never race an in-flight consumer or delete its claimed file.
            raise SetupBridgeError("handoff-unknown")
        incoming_exists = PinnedPymobiledeviceAdapter._remote_exists(service, V1_INCOMING)
        retiring_exists = PinnedPymobiledeviceAdapter._remote_exists(service, retiring)
        if incoming_exists and retiring_exists:
            raise SetupBridgeError("transaction-unknown")
        if not incoming_exists and not retiring_exists:
            return
        if incoming_exists:
            # Rename out of iOS's well-known consumer path first. The Mac
            # retire operation and iOS consume operation now have one atomic
            # winner, and validation/deletion target this exact object.
            try:
                _run(service.rename(V1_INCOMING, retiring))
            except Exception:
                if PinnedPymobiledeviceAdapter._remote_exists(service, consuming):
                    raise SetupBridgeError("handoff-unknown") from None
                raise SetupBridgeError("transaction-unknown") from None
            if PinnedPymobiledeviceAdapter._remote_exists(service, V1_INCOMING):
                raise SetupBridgeError("transaction-unknown")
            if not PinnedPymobiledeviceAdapter._remote_exists(service, retiring):
                raise SetupBridgeError("handoff-unknown")
        raw = PinnedPymobiledeviceAdapter._read_remote_bounded(
            service, retiring, max_bytes=1 * 1024 * 1024 + 64 * 1024
        )
        try:
            value = plistlib.loads(raw)
            if (
                not isinstance(value, Mapping)
                or set(value) != {"version", "transactionID", "expectedDeviceUDID", "pairingFile", "sha256"}
                or type(value.get("version")) is not int
                or value.get("version") != 1
                or str(uuid.UUID(value.get("transactionID"))).lower() != transaction_id
                or normalized_device(value.get("expectedDeviceUDID")) != normalized_device(device_id)
                or not isinstance(value.get("pairingFile"), bytes)
                or not isinstance(value.get("sha256"), bytes)
                or hashlib.sha256(value["pairingFile"]).digest() != value["sha256"]
            ):
                raise ValueError("mismatched pairing input")
        except Exception:
            if not PinnedPymobiledeviceAdapter._remote_exists(service, V1_INCOMING):
                try:
                    _run(service.rename(retiring, V1_INCOMING))
                except Exception:
                    raise SetupBridgeError("transaction-unknown") from None
            raise SetupBridgeError("transaction-conflict") from None
        try:
            _run(service.rm_single(retiring, force=True))
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        if (PinnedPymobiledeviceAdapter._remote_exists(service, retiring)
                or PinnedPymobiledeviceAdapter._remote_exists(service, V1_INCOMING)
                or PinnedPymobiledeviceAdapter._remote_exists(service, consuming)):
            raise SetupBridgeError("handoff-unknown")

    def prepare_setup_input(
        self,
        device_id: str,
        setup_id: str,
        nonce: str,
        artifact: ArtifactIdentity,
        pairing_transaction_id: str,
        pairing_sha256: str,
        support: Mapping[str, Any],
        *,
        plan: FormalSetupInput,
        transport: str = "usb",
    ) -> str:
        """Upload validated DDI bytes, then publish the manifest last."""
        if self.state_root is None:
            raise SetupBridgeError("configuration-invalid")
        method = support.get("method")
        os_version = support.get("osVersion")
        if method not in {"personalized", "cryptex"} or not isinstance(os_version, str):
            raise SetupBridgeError("support-unavailable")
        try:
            from .setup_support import validate_generation
        except ImportError:
            from setup_support import validate_generation
        restore = self.state_root / "transactions" / _uuid(setup_id) / "support"
        generation = validate_generation(method, restore)
        names = ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
        if method == "cryptex":
            names.extend(["Image.dmg.cryptex_info", "Image.dmg.root_hash"])
        if not isinstance(plan, FormalSetupInput):
            raise SetupBridgeError("handoff-unknown")
        actual_files = {
            label: [pair[0], pair[1]]
            for label, pair in generation.files.items()
        }
        actual_support = dict(support)
        actual_support["inputFiles"] = actual_files
        actual_support["inputManifestSHA256"] = generation.manifest_sha256
        actual_plan = build_formal_setup_input(
            device_id=device_id,
            setup_id=setup_id,
            nonce=nonce,
            artifact=artifact,
            pairing_transaction_id=pairing_transaction_id,
            pairing_sha256=pairing_sha256,
            support=actual_support,
        )
        if actual_plan != plan:
            raise SetupBridgeError("handoff-unknown")
        raw_manifest = plan.raw_manifest
        self._formal_inventories[(_uuid(setup_id), _uuid(nonce))] = plan.artifacts
        self._decode_formal_manifest(raw_manifest, device_id=device_id, setup_id=setup_id, nonce=nonce)
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-input-") as directory:
                client = self._open(device_id, Path(directory), transport)
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, self._target_bundle_id(), documents_only=False))
                _run(service.makedirs(f"{FORMAL_GENERATIONS}/{_uuid(setup_id)}/DDI"))
                for filename in names:
                    self._upload_remote_file(
                        service,
                        restore / filename,
                        f"{FORMAL_GENERATIONS}/{_uuid(setup_id)}/DDI/{filename}",
                    )
                self._publish_on_service(service, FORMAL_INPUT, raw_manifest)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())
        return plan.sha256

    def formal_inventory(self, setup_id: str, nonce: str) -> tuple[tuple[str, str, int, str], ...]:
        """Return the immutable inventory selected for the exact formal nonce."""
        key = (_uuid(setup_id), _uuid(nonce))
        try:
            return self._formal_inventories[key]
        except KeyError:
            raise SetupBridgeError("handoff-unknown") from None

    def _publish_house_arrest(self, device_id: str, remote: str, data: bytes, *, conflict_code: str) -> None:
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-upload-") as directory:
                client = self._open(device_id, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, self._target_bundle_id(), documents_only=False))
                parent = remote.rsplit("/", 1)[0] if "/" in remote else ""
                if parent:
                    _run(service.makedirs(parent))
                self._publish_on_service(service, remote, data, conflict_code=conflict_code)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError(conflict_code) from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def _publish_on_service(self, service: Any, remote: str, data: bytes, *, conflict_code: str = "handoff-unknown") -> None:
        existing = self._remote_exists(service, remote)
        if existing:
            current = self._read_remote_bounded(service, remote)
            if current != data:
                raise SetupBridgeError("transaction-conflict")
            return
        temporary = remote + ".staging"
        if self._remote_exists(service, temporary):
            raise SetupBridgeError("transaction-unknown")
        _run(service.set_file_contents(temporary, data))
        staged = self._read_remote_bounded(service, temporary)
        if staged != data:
            raise SetupBridgeError(conflict_code)
        _run(service.rename(temporary, remote))
        published = self._read_remote_bounded(service, remote)
        if published != data:
            raise SetupBridgeError(conflict_code)

    @staticmethod
    def _upload_remote_file(service: Any, local: Path, remote: str) -> None:
        size, digest = _stream_hash(local)
        if PinnedPymobiledeviceAdapter._remote_exists(service, remote):
            info = _run(service.stat(remote))
            if isinstance(info, Mapping) and info.get("st_ifmt") == "S_IFREG" and int(info.get("st_size", -1)) == size:
                if PinnedPymobiledeviceAdapter._remote_sha256(service, remote) == digest:
                    return
                raise SetupBridgeError("transaction-conflict")
            raise SetupBridgeError("storage-unavailable")
        temporary = remote + ".staging"
        _run(service.push(local, temporary, progress_bar=False))
        info = PinnedPymobiledeviceAdapter._remote_info(service, temporary)
        if info["size"] != size:
            raise SetupBridgeError("handoff-unknown")
        if PinnedPymobiledeviceAdapter._remote_sha256(service, temporary) != digest:
            raise SetupBridgeError("handoff-unknown")
        _run(service.rename(temporary, remote))
        published = PinnedPymobiledeviceAdapter._remote_info(service, remote)
        if published["size"] != size or PinnedPymobiledeviceAdapter._remote_sha256(service, remote) != digest:
            raise SetupBridgeError("handoff-unknown")

    @staticmethod
    def _remote_sha256(service: Any, remote: str) -> str:
        async def digest_remote() -> str:
            info = await service.stat(remote)
            if not isinstance(info, Mapping) or info.get("st_ifmt") != "S_IFREG":
                raise ValueError("not regular")
            size = info.get("st_size")
            if type(size) is not int or size < 0 or size > MAX_ARTIFACT_BYTES:
                raise ValueError("unsafe remote size")
            handle = await service.fopen(remote, "r")
            digest = hashlib.sha256()
            try:
                remaining = size
                while remaining:
                    chunk = await service.fread(handle, min(1024 * 1024, remaining))
                    if not isinstance(chunk, bytes) or not chunk or len(chunk) > remaining:
                        raise ValueError("short remote read")
                    digest.update(chunk)
                    remaining -= len(chunk)
                sentinel = await service.fread(handle, 1)
                if not isinstance(sentinel, bytes) or sentinel:
                    raise ValueError("remote grew during read")
                final = await service.stat(remote)
                if (
                    not isinstance(final, Mapping)
                    or final.get("st_ifmt") != "S_IFREG"
                    or type(final.get("st_size")) is not int
                    or final.get("st_size") != size
                ):
                    raise ValueError("remote changed during read")
                return digest.hexdigest()
            finally:
                await service.fclose(handle)
        try:
            return _run(digest_remote())
        except Exception:
            raise SetupBridgeError("transaction-unknown") from None

    @staticmethod
    def _remote_info(service: Any, path: str) -> dict[str, int]:
        try:
            info = _run(service.stat(path))
        except OSError as error:
            if _is_remote_missing(error):
                raise _RemoteMissing() from None
            raise SetupBridgeError("handoff-unknown") from None
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        if not isinstance(info, Mapping) or info.get("st_ifmt") != "S_IFREG":
            raise SetupBridgeError("storage-unavailable")
        size = info.get("st_size")
        if type(size) is not int or size < 0 or size > MAX_ARTIFACT_BYTES:
            raise SetupBridgeError("storage-unavailable")
        return {"size": size}

    @staticmethod
    def _read_remote_bounded(service: Any, path: str, *, max_bytes: int = MAX_ARTIFACT_BYTES) -> bytes:
        try:
            info = PinnedPymobiledeviceAdapter._remote_info(service, path)
        except _RemoteMissing:
            raise SetupBridgeError("transaction-unknown") from None
        if info["size"] > max_bytes:
            raise SetupBridgeError("storage-unavailable")
        async def read_remote() -> bytes:
            declared = info["size"]
            handle = await service.fopen(path, "r")
            data = bytearray()
            try:
                remaining = declared
                while remaining:
                    chunk = await service.fread(handle, min(1024 * 1024, remaining))
                    if not isinstance(chunk, bytes) or not chunk or len(chunk) > remaining:
                        raise ValueError("short remote read")
                    data.extend(chunk)
                    remaining -= len(chunk)
                # A one-byte sentinel detects growth after the stat.  The
                # request is bounded and is made before any post-read trust.
                sentinel = await service.fread(handle, 1)
                if not isinstance(sentinel, bytes) or sentinel:
                    raise ValueError("remote grew during read")
                final = await service.stat(path)
                if (
                    not isinstance(final, Mapping)
                    or final.get("st_ifmt") != "S_IFREG"
                    or type(final.get("st_size")) is not int
                    or final.get("st_size") != declared
                ):
                    raise ValueError("remote changed during read")
                return bytes(data)
            finally:
                await service.fclose(handle)
        try:
            data = _run(read_remote())
        except OSError as error:
            if _is_remote_missing(error):
                raise SetupBridgeError("transaction-unknown") from None
            raise SetupBridgeError("handoff-unknown") from None
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        if not isinstance(data, bytes) or len(data) != info["size"] or len(data) > max_bytes:
            raise SetupBridgeError("handoff-unknown")
        return data

    @staticmethod
    def _remote_exists(service: Any, path: str) -> bool:
        try:
            PinnedPymobiledeviceAdapter._remote_info(service, path)
            return True
        except _RemoteMissing:
            return False
        except SetupBridgeError:
            raise

    @staticmethod
    def _decode_readback(
        data: bytes, *, device_id: str, setup_id: str, nonce: str, target_bundle_id: str
    ) -> ReadbackObservation:
        try:
            value = _parse_object(data, limit=64 * 1024)
            if set(value) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app", "pairing"}:
                raise ValueError()
            if type(value.get("version")) is not int or value["version"] != 1:
                raise ValueError()
            if _uuid(value.get("setupID")) != _uuid(setup_id) or _uuid(value.get("nonce")) != _uuid(nonce):
                raise ValueError()
            expected = normalized_device(value.get("expectedDeviceUDID"))
            selected = normalized_device(device_id)
            if expected != selected:
                raise ValueError()
            app = value.get("app")
            if not isinstance(app, Mapping) or set(app) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
                raise ValueError()
            if (
                app.get("bundleID") != target_bundle_id
                or not isinstance(app.get("build"), str)
                or not app["build"]
                or len(app["build"].encode("utf-8")) > MAX_BUILD_BYTES
            ):
                raise ValueError()
            profile = app.get("profileSHA256")
            executable = app.get("executableSHA256")
            if not isinstance(profile, str) or not re.fullmatch(r"[0-9a-f]{64}", profile):
                raise ValueError()
            if not isinstance(executable, str) or not re.fullmatch(r"[0-9a-f]{64}", executable):
                raise ValueError()
            pairing = value.get("pairing")
            if not isinstance(pairing, Mapping) or not isinstance(pairing.get("kind"), str):
                raise ValueError()
            kind = pairing["kind"]
            if kind in {"absent", "invalid"}:
                if set(pairing) != {"kind"}:
                    raise ValueError()
                pairing_sha = ""
            elif kind == "verified":
                if set(pairing) != {"kind", "expectedDeviceUDID", "sha256"}:
                    raise ValueError()
                if normalized_device(pairing.get("expectedDeviceUDID")) != selected:
                    raise ValueError()
                pairing_sha = pairing.get("sha256")
                if not isinstance(pairing_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", pairing_sha):
                    raise ValueError()
            else:
                raise ValueError()
            return ReadbackObservation(
                _uuid(nonce), _uuid(setup_id), selected, "", executable, profile,
                pairing_sha, build=app["build"],
            )
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None

    @staticmethod
    def _decode_formal_manifest(
        data: bytes, *, device_id: str, setup_id: str, nonce: str
    ) -> Mapping[str, Any]:
        """Validate the exact formal input before publishing it to the App."""
        try:
            value = _parse_object(data, limit=MAX_MANIFEST_BYTES)
            expected_keys = {
                "version", "setupID", "nonce", "expectedDeviceUDID", "pairingTransactionID", "pairingSHA256",
                "app", "teamID", "signingExpiry", "deviceOS", "method", "artifacts",
            }
            if set(value) != expected_keys or value.get("version") != 1:
                raise ValueError()
            if _uuid(value.get("setupID")) != _uuid(setup_id) or _uuid(value.get("nonce")) != _uuid(nonce):
                raise ValueError()
            if normalized_device(value.get("expectedDeviceUDID")) != normalized_device(device_id):
                raise ValueError()
            _uuid(value.get("pairingTransactionID"))
            if not isinstance(value.get("pairingSHA256"), str) or re.fullmatch(r"[0-9a-f]{64}", value["pairingSHA256"]) is None:
                raise ValueError()
            team_id = value.get("teamID")
            if not isinstance(team_id, str) or re.fullmatch(r"[A-Z0-9]{10}", team_id) is None:
                raise ValueError()
            app = value.get("app")
            if not isinstance(app, Mapping) or set(app) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
                raise ValueError()
            if not bundle_id_matches_team(app.get("bundleID"), team_id) or not isinstance(app.get("build"), str) or not app["build"]:
                raise ValueError()
            if not isinstance(app.get("profileSHA256"), str) or re.fullmatch(r"[0-9a-f]{64}", app["profileSHA256"]) is None:
                raise ValueError()
            if not isinstance(app.get("executableSHA256"), str) or re.fullmatch(r"[0-9a-f]{64}", app["executableSHA256"]) is None:
                raise ValueError()
            if not isinstance(value.get("signingExpiry"), str) or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value["signingExpiry"]) is None:
                raise ValueError()
            os_version = value.get("deviceOS")
            method = value.get("method")
            if not isinstance(os_version, str) or not re.fullmatch(r"(?:26|27)(?:\.\d+){1,2}", os_version):
                raise ValueError()
            if method not in {"personalized", "cryptex"}:
                raise ValueError()
            parts = [int(part) for part in os_version.split(".")]
            expected_method = "personalized" if parts[0] == 26 and len(parts) > 1 and parts[1] <= 3 else "cryptex"
            if method != expected_method:
                raise ValueError()
            names = ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
            if method == "cryptex":
                names.extend(["Image.dmg.cryptex_info", "Image.dmg.root_hash"])
            artifacts = value.get("artifacts")
            if not isinstance(artifacts, list) or len(artifacts) != len(names):
                raise ValueError()
            by_name: dict[str, Mapping[str, Any]] = {}
            seen_ids: set[str] = set()
            total = 0
            for artifact in artifacts:
                if not isinstance(artifact, Mapping) or set(artifact) != {"id", "filename", "byteCount", "sha256"}:
                    raise ValueError()
                artifact_id = _uuid(artifact.get("id"))
                filename = artifact.get("filename")
                size = artifact.get("byteCount")
                digest = artifact.get("sha256")
                if filename not in names or filename in by_name or artifact_id in seen_ids:
                    raise ValueError()
                if type(size) is not int or size <= 0 or size > MAX_ARTIFACT_BYTES:
                    raise ValueError()
                if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                    raise ValueError()
                total += size
                if total > MAX_ARTIFACT_BYTES:
                    raise ValueError()
                by_name[filename] = artifact
                seen_ids.add(artifact_id)
            if set(by_name) != set(names):
                raise ValueError()
            mount = by_name["MountMethod"]
            if mount["byteCount"] != len(method.encode("ascii")) or mount["sha256"] != hashlib.sha256(method.encode("ascii")).hexdigest():
                raise ValueError()
            return value
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None

    @staticmethod
    def _decode_activation_receipt(
        data: bytes, *, device_id: str, setup_id: str, nonce: str
    ) -> ActivationReceiptObservation:
        """Decode the App-owned activation record and select one exact receipt.

        The App stores a bounded activation record, rather than a bare receipt.
        A matching receipt is useful only after every nested field and artifact
        entry has passed the same closed validation as the frozen A contract.
        """
        try:
            value = _parse_object(data, limit=256 * 1024)
            if set(value) != {"version", "activeSetupID", "receipts"}:
                raise ValueError()
            if type(value["version"]) is not int or value["version"] != 1:
                raise ValueError()
            active = value["activeSetupID"]
            if not isinstance(active, str):
                raise ValueError()
            active = _uuid(active)
            receipts = value["receipts"]
            if not isinstance(receipts, list) or not receipts or len(receipts) > 128:
                raise ValueError()
            selected = normalized_device(device_id)
            expected_setup = _uuid(setup_id)
            expected_nonce = _uuid(nonce)
            matches: list[ActivationReceiptObservation] = []
            seen_receipt_ids: set[tuple[str, str]] = set()
            seen_setup_ids: set[str] = set()
            seen_nonces: set[str] = set()
            for receipt in receipts:
                if not isinstance(receipt, Mapping):
                    raise ValueError()
                receipt_keys = {
                    "version", "setupID", "nonce", "expectedDeviceUDID",
                    "rawManifestSHA256", "pairingTransactionID", "pairingSHA256",
                    "app", "teamID", "signingExpiry", "deviceOS", "method",
                    "generationID", "artifacts", "status",
                }
                if set(receipt) != receipt_keys:
                    raise ValueError()
                if type(receipt["version"]) is not int or receipt["version"] != 1:
                    raise ValueError()
                receipt_setup = _uuid(receipt["setupID"])
                receipt_nonce = _uuid(receipt["nonce"])
                receipt_identity = (receipt_setup, receipt_nonce)
                if (
                    receipt_identity in seen_receipt_ids
                    or receipt_setup in seen_setup_ids
                    or receipt_nonce in seen_nonces
                ):
                    raise ValueError()
                seen_receipt_ids.add(receipt_identity)
                seen_setup_ids.add(receipt_setup)
                seen_nonces.add(receipt_nonce)
                receipt_device = normalized_device(receipt["expectedDeviceUDID"])
                if receipt_device != selected:
                    raise ValueError()
                raw_manifest = receipt["rawManifestSHA256"]
                pairing_tx = _uuid(receipt["pairingTransactionID"])
                pairing_sha = receipt["pairingSHA256"]
                if not isinstance(raw_manifest, str) or not re.fullmatch(r"[0-9a-f]{64}", raw_manifest):
                    raise ValueError()
                if not isinstance(pairing_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", pairing_sha):
                    raise ValueError()
                team = receipt["teamID"]
                if not isinstance(team, str) or re.fullmatch(r"[A-Z0-9]{10}", team) is None:
                    raise ValueError()
                app = receipt["app"]
                if not isinstance(app, Mapping) or set(app) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
                    raise ValueError()
                if (
                    not bundle_id_matches_team(app.get("bundleID"), team)
                    or not isinstance(app.get("build"), str)
                    or not app["build"]
                    or len(app["build"].encode("utf-8")) > MAX_BUILD_BYTES
                ):
                    raise ValueError()
                profile = app["profileSHA256"]
                executable = app["executableSHA256"]
                if not isinstance(profile, str) or not re.fullmatch(r"[0-9a-f]{64}", profile):
                    raise ValueError()
                if not isinstance(executable, str) or not re.fullmatch(r"[0-9a-f]{64}", executable):
                    raise ValueError()
                expiry = receipt["signingExpiry"]
                if not isinstance(expiry, str) or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", expiry) is None:
                    raise ValueError()
                parsed_expiry = dt.datetime.fromisoformat(expiry.replace("Z", "+00:00"))
                if parsed_expiry.tzinfo is None:
                    raise ValueError()
                device_os = receipt["deviceOS"]
                if not isinstance(device_os, str) or re.fullmatch(r"\d+(?:\.\d+){0,2}", device_os) is None:
                    raise ValueError()
                os_parts = [int(part) for part in device_os.split(".")]
                if len(os_parts) < 2 or os_parts[0] < 26:
                    raise ValueError()
                method = receipt["method"]
                if method not in {"personalized", "cryptex"}:
                    raise ValueError()
                if os_parts[0] == 26 and (len(os_parts) == 1 or os_parts[1] <= 3):
                    if method != "personalized":
                        raise ValueError()
                elif method != "cryptex":
                    raise ValueError()
                generation = _uuid(receipt["generationID"])
                if generation != receipt_setup:
                    raise ValueError()
                artifacts = receipt["artifacts"]
                if not isinstance(artifacts, list):
                    raise ValueError()
                required_names = {
                    "MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache",
                }
                if method == "cryptex":
                    required_names |= {"Image.dmg.cryptex_info", "Image.dmg.root_hash"}
                if len(artifacts) != len(required_names):
                    raise ValueError()
                seen_names: set[str] = set()
                artifact_values: list[tuple[str, int, str]] = []
                artifact_records: list[tuple[str, str, int, str]] = []
                total_bytes = 0
                for artifact in artifacts:
                    if not isinstance(artifact, Mapping) or set(artifact) != {"id", "filename", "byteCount", "sha256"}:
                        raise ValueError()
                    filename = artifact["filename"]
                    if not isinstance(filename, str) or filename not in required_names or filename in seen_names:
                        raise ValueError()
                    artifact_id = _uuid(artifact["id"])
                    byte_count = artifact["byteCount"]
                    if type(byte_count) is not int or byte_count <= 0 or byte_count > MAX_ARTIFACT_BYTES:
                        raise ValueError()
                    total_bytes += byte_count
                    if total_bytes > MAX_ARTIFACT_BYTES:
                        raise ValueError()
                    digest = artifact["sha256"]
                    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                        raise ValueError()
                    seen_names.add(filename)
                    artifact_values.append((filename, byte_count, digest))
                    artifact_records.append((artifact_id, filename, byte_count, digest))
                if seen_names != required_names or receipt["status"] != "committed":
                    raise ValueError()
                if receipt_setup == expected_setup and receipt_nonce == expected_nonce:
                    matches.append(
                        ActivationReceiptObservation(
                            receipt_setup,
                            receipt_nonce,
                            receipt_device,
                            raw_manifest,
                            pairing_tx,
                            pairing_sha,
                            app["bundleID"],
                            app["build"],
                            profile,
                            executable,
                            team,
                            expiry,
                            device_os,
                            method,
                            generation,
                            tuple(artifact_values),
                            tuple(artifact_records),
                        )
                    )
            if active not in {identity[0] for identity in seen_receipt_ids}:
                raise ValueError()
            if sum(1 for identity in seen_receipt_ids if identity[0] == active) != 1:
                raise ValueError()
            if len(matches) != 1:
                raise ValueError()
            return matches[0]
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None

    def readback(self, device_id: str, setup_id: str, nonce: str) -> ReadbackObservation | None:
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-readback-") as directory:
                client = self._open(device_id, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, self._target_bundle_id(), documents_only=False))
                data = self._read_remote_bounded(service, READBACK_RESPONSE, max_bytes=64 * 1024)
                return self._decode_readback(
                    data, device_id=device_id, setup_id=setup_id, nonce=nonce,
                    target_bundle_id=self._target_bundle_id(),
                )
        except SetupBridgeError as error:
            if error.code == "transaction-unknown":
                return None
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def read_activation_receipt(
        self, device_id: str, setup_id: str, nonce: str, transport: str = "usb"
    ) -> ActivationReceiptObservation | None:
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-setup-activation-") as directory:
                client = self._open(device_id, Path(directory), transport)
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, self._target_bundle_id(), documents_only=False))
                data = self._read_remote_bounded(service, ACTIVATION_RECEIPT, max_bytes=256 * 1024)
                receipt = self._decode_activation_receipt(
                    data, device_id=device_id, setup_id=setup_id, nonce=nonce
                )
                if receipt is not None and receipt.bundle_id != self._target_bundle_id():
                    raise SetupBridgeError("handoff-unknown")
                return receipt
        except SetupBridgeError as error:
            if error.code == "transaction-unknown":
                return None
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def query_support(self, device_id: str, method: str, transport: str = "usb") -> SupportObservation:
        try:
            from .setup_support import PinnedSupportAdapter
        except ImportError:
            from setup_support import PinnedSupportAdapter
        return PinnedSupportAdapter(self).query(device_id, method, transport)

    def install_support(
        self, device_id: str, method: str, restore_dir: Path, transport: str = "usb"
    ) -> SupportObservation:
        try:
            from .setup_support import PinnedSupportAdapter
        except ImportError:
            from setup_support import PinnedSupportAdapter
        return PinnedSupportAdapter(self).install(device_id, method, restore_dir, transport)

    def prepare_generation(self, method: str, restore_dir: Path) -> Any:
        """Materialize and validate one transaction-private support inventory."""
        try:
            from .setup_support import PinnedSupportAdapter
        except ImportError:
            from setup_support import PinnedSupportAdapter
        adapter = PinnedSupportAdapter(self)
        return adapter.prepare_generation(method, restore_dir)

    @contextlib.asynccontextmanager
    async def _process_control(self, device_id: str, transport_serial: str, transport: str = "usb"):
        """iOS 26/27 DVT is exposed through same-device RSD, not Lockdown."""
        userspace = importlib.import_module("pymobiledevice3.remote.userspace_tunnel")
        module = importlib.import_module("pymobiledevice3.services.dvt.instruments.process_control")
        provider_module = importlib.import_module("pymobiledevice3.services.dvt.instruments.dvt_provider")
        tunnel_cls = getattr(userspace, "UserspaceRsdTunnel", None)
        control_cls = getattr(module, "ProcessControl", None)
        provider_cls = getattr(provider_module, "DvtProvider", None)
        if tunnel_cls is None or control_cls is None or provider_cls is None:
            raise SetupBridgeError("runtime-api-mismatch")
        tunnel = tunnel_cls(serial=transport_serial, autopair=False, remotepairing_fallback=False)
        try:
            rsd = await tunnel.aopen()
            if str(getattr(rsd, "udid", "")).lower() != device_id.lower():
                raise SetupBridgeError("identity-mismatch")
            if not re.fullmatch(r"(?:26|27)\.\d+(?:\.\d+)?", str(getattr(rsd, "product_version", ""))):
                raise SetupBridgeError("unsupported-os")
            async with provider_cls(rsd) as provider:
                async with control_cls(provider) as control:
                    yield control
        finally:
            await tunnel.aclose()

    def launch(self, device_id: str, transport: str = "usb") -> int:
        try:
            # Resolve the transport outside the async operation: all pmd services share
            # the operation loop, and _run must not be nested inside that loop.
            serial = self.tunnel_serial(device_id, transport)

            async def launch_checked() -> int:
                async with self._process_control(device_id, serial, transport) as control:
                    target_bundle_id = self._target_bundle_id()
                    existing = await control.process_identifier_for_bundle_identifier(target_bundle_id)
                    if existing:
                        raise SetupBridgeError("app-running")
                    pid = await control.launch(target_bundle_id, kill_existing=False)
                    if type(pid) is not int or pid <= 0:
                        raise SetupBridgeError("handoff-unknown")
                    return pid

            pid = _run(launch_checked())
            self._process_pids[device_id.lower()] = pid
            return pid
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None

    def stop(
        self, device_id: str, expected_pid: int | None = None, transport: str = "usb"
    ) -> None:
        expected = self._process_pids.get(device_id.lower())
        if expected_pid is not None:
            if expected is not None and expected_pid != expected:
                raise SetupBridgeError("handoff-unknown")
            expected = expected_pid
        if type(expected) is not int or expected <= 0:
            raise SetupBridgeError("handoff-unknown")
        try:
            serial = self.tunnel_serial(device_id, transport)

            async def stop_checked() -> None:
                async with self._process_control(device_id, serial, transport) as control:
                    current = await control.process_identifier_for_bundle_identifier(self._target_bundle_id())
                    if current == 0:
                        return
                    if current != expected:
                        raise SetupBridgeError("handoff-unknown")
                    await control.kill(expected)

            _run(stop_checked())
            self._process_pids.pop(device_id.lower(), None)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
