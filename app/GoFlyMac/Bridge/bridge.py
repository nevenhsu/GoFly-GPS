#!/usr/bin/env python3
"""Small, read-only JSON bridge used by the GoFly macOS setup UI.

The process has one request and one response.  It deliberately keeps the
device dependency behind a narrow adapter so the same protocol can be tested
without an iPhone or Xcode.  The product scope is read-only.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import contextvars
import importlib.util
import io
import json
import logging
import os
import plistlib
import re
import selectors
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping


# Bundled legacy helpers are imported at runtime.  Avoid producing bytecode
# beside either the packaged helper or the workspace fallback.
sys.dont_write_bytecode = True


try:
    from .wire import (
        MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES, SAFE_ERROR_CODES, UUID_RE, TEAM_RE,
        WireError, action as wire_action, encode as wire_encode, emit as wire_emit,
        parse_object, read_request, request_id as wire_request_id, response as wire_response,
    )
except ImportError:  # direct script execution from the Bridge directory
    # ProcessBridge launches this file with `python -I`, which does not add the
    # script directory to sys.path.  Restore the sibling module lookup so the
    # packaged `wire.py` is importable.
    _bridge_root = str(Path(__file__).resolve().parent)
    if _bridge_root not in sys.path:
        sys.path.insert(0, _bridge_root)
    from wire import (
        MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES, SAFE_ERROR_CODES, UUID_RE, TEAM_RE,
        WireError, action as wire_action, encode as wire_encode, emit as wire_emit,
        parse_object, read_request, request_id as wire_request_id, response as wire_response,
    )

BridgeError = WireError
DEFAULT_TARGET_NAME = "GoFly"
LOCALDEVVPN_BUNDLE_ID = "com.jkcoxson.LocalDevVPN"
MINIMUM_FREE_SPACE_GB = 40
PLANNED_XCODE_MINIMUM_MACOS_VERSION = "26.6"
USB = "USB"
NETWORK = "Network"
SUPPORTED_OS_MAJOR = 26
UDID_RE = re.compile(r"(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{40})\Z")
_ACTIVE_RUNNER: contextvars.ContextVar[asyncio.Runner | None] = contextvars.ContextVar(
    "gofly_active_runner", default=None
)


@dataclass(frozen=True)
class Config:
    resources_root: Path
    python_path: Path
    developer_directory: Path
    project_path: Path
    target_name: str = DEFAULT_TARGET_NAME
    state_root: Path = field(default_factory=lambda: Path.home() / "Library" / "Application Support" / "GoFly" / "state")

    @classmethod
    def from_bundle(
        cls,
        resources_root: str | Path,
        developer_directory: str | Path,
        target_name: str = DEFAULT_TARGET_NAME,
    ) -> "Config":
        resources = Path(resources_root)
        if (
            not resources.is_absolute()
            or resources.is_symlink()
            or not resources.is_dir()
            or not isinstance(target_name, str)
            or not 1 <= len(target_name) <= 200
            or not _bundle_resources_valid(resources)
        ):
            raise BridgeError("bundle-damaged")
        return cls(
            resources_root=resources,
            python_path=resources / "Python" / "python" / "install" / "bin" / "python3.14",
            developer_directory=Path(developer_directory),
            project_path=resources / "iOSProject" / "GoFly.xcodeproj",
            target_name=target_name,
            state_root=Path.home() / "Library" / "Application Support" / "GoFly" / "state",
        )


def _bundle_resources_valid(resources: Path) -> bool:
    """Validate required bundled inputs before exposing environment checks."""
    files = (
        "Python/python/install/bin/python3.14",
        "Bridge/bridge.py",
        "Bridge/wire.py",
        "Bridge/Device/gofly_device.py",
        "Bridge/Setup/setup_protocol.py",
        "Bridge/Setup/setup_config.py",
        "Bridge/Setup/setup_journal.py",
        "Bridge/Setup/setup_producer.py",
        "Bridge/Setup/setup_adapters.py",
        "Bridge/Setup/setup_support.py",
        "iOSProject/GoFly.xcodeproj/project.pbxproj",
        "iOSProject/GoFly.xcconfig",
        "native/libidevice_ffi.a",
    )
    directories = (
        "Python/python/install/lib/python3.14/site-packages",
        "Bridge/Device",
        "Bridge/Setup",
        "iOSProject/GoFly.xcodeproj",
    )
    try:
        if any((resources / relative).is_symlink() or not (resources / relative).is_file() for relative in files):
            return False
        interpreter = resources / files[0]
        if not os.access(interpreter, os.X_OK):
            return False
        if any((resources / relative).is_symlink() or not (resources / relative).is_dir() for relative in directories):
            return False
    except OSError:
        return False
    return True


def _load_module(path: Path, name: str) -> Any:
    if path.is_symlink() or not path.is_file():
        raise BridgeError("bundle-damaged")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise BridgeError("bundle-damaged")
    module = importlib.util.module_from_spec(spec)
    # Use a private module name so a different invocation cannot accidentally
    # reuse a module loaded from an arbitrary working directory.
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise BridgeError("bundle-damaged") from None
    return module


def load_device_module(config: Config) -> Any:
    """Load only the read-only device boundary inside the app bundle."""
    path = config.resources_root / "Bridge" / "Device" / "gofly_device.py"
    if path.is_symlink() or not path.is_file():
        raise BridgeError("bundle-damaged")
    return _load_module(path, "_gofly_device_boundary")


@contextlib.contextmanager
def quiet_dependencies() -> Iterable[None]:
    """Prevent library diagnostics from corrupting the one-line protocol."""

    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try:
            yield
        finally:
            logging.disable(previous)


def _await(value: Any) -> Any:
    if not asyncio.iscoroutine(value) and not isinstance(value, asyncio.Future):
        return value
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        runner = _ACTIVE_RUNNER.get()
        if runner is not None:
            return runner.run(value)
        return asyncio.run(value)
    raise BridgeError("operation-failed")


def _new_async_runner() -> Any:
    factory = getattr(asyncio, "Runner", None)
    if factory is not None:
        return factory()
    class LegacyRunner:
        def __init__(self) -> None:
            self.loop = asyncio.new_event_loop()
        def run(self, value: Any) -> Any:
            return self.loop.run_until_complete(value)
        def close(self) -> None:
            self.loop.close()
    return LegacyRunner()


def _normalized_udid(value: Any) -> str | None:
    if not isinstance(value, str) or not UDID_RE.fullmatch(value.strip()):
        return None
    return value.strip().lower()


def _value(item: Any, *names: str) -> Any:
    if isinstance(item, Mapping):
        for name in names:
            if name in item:
                return item[name]
    for name in names:
        try:
            result = getattr(item, name)
        except Exception:
            continue
        if result is not None:
            return result
    return None


def _transport(item: Any) -> str | None:
    value = _value(item, "connection_type", "ConnectionType", "connectionType")
    if isinstance(value, str):
        value = value.strip().lower()
        if value == "usb":
            return "usb"
        if value in {"network", "wifi", "wi-fi"}:
            return "wifi"
    if _value(item, "is_usb", "isUSB") is True:
        return "usb"
    if _value(item, "is_network", "isNetwork") is True:
        return "wifi"
    return None


def _version_supported(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    match = re.match(r"\s*(\d+)(?:\.\d+)*\s*\Z", value)
    return bool(match and int(match.group(1)) >= SUPPORTED_OS_MAJOR)


def _version_tuple(value: Any) -> tuple[int, ...] | None:
    if not isinstance(value, str) or re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", value) is None:
        return None
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (4 - len(parts)))


def _safe_process(arguments: list[str], *, env: Mapping[str, str] | None = None, timeout: int = 30) -> tuple[int, bytes]:
    """Run one fixed command while bounding captured stdout and stderr."""

    process: subprocess.Popen[bytes] | None = None
    selector: selectors.BaseSelector | None = None
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=dict(env) if env is not None else None,
        )
        assert process.stdout is not None and process.stderr is not None
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ, False)
        selector.register(process.stderr, selectors.EVENT_READ, True)
        output = bytearray()
        deadline = time.monotonic() + timeout
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(arguments, timeout)
            for key, _ in selector.select(remaining):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if not key.data:
                    if len(output) + len(chunk) > 64 * 1024:
                        raise BridgeError("operation-failed")
                    output.extend(chunk)
        return process.wait(timeout=max(0.1, deadline - time.monotonic())), bytes(output)
    except BridgeError:
        if process is not None:
            with contextlib.suppress(OSError):
                process.kill()
            with contextlib.suppress(Exception):
                process.communicate(timeout=1)
        raise
    except (OSError, subprocess.TimeoutExpired):
        if process is not None:
            with contextlib.suppress(OSError):
                process.kill()
            with contextlib.suppress(Exception):
                process.communicate(timeout=1)
        raise BridgeError("operation-failed") from None
    finally:
        if selector is not None:
            selector.close()
        if process is not None:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    with contextlib.suppress(OSError):
                        stream.close()


class Bridge:
    def __init__(self, config: Config, device: Any | None = None):
        self.config = config
        self._device = device

    @property
    def device(self) -> Any:
        if self._device is None:
            self._device = load_device_module(self.config)
        return self._device

    def _raw_devices(self) -> list[Any]:
        device = self.device
        check = getattr(device, "check_compatibility", None)
        list_devices = getattr(device, "list_usb_devices", None)
        if not callable(check) or not callable(list_devices):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                check()
                result = _await(list_devices())
        except BridgeError:
            raise
        except Exception as error:
            code = getattr(error, "code", "")
            raise BridgeError(_map_error(code or "operation-failed")) from None
        if not isinstance(result, list):
            raise BridgeError("operation-failed")
        return result

    def _device_rows(self, raw: list[Any]) -> list[dict[str, Any]]:
        selected: dict[tuple[str, str], dict[str, Any]] = {}
        for item in raw:
            transport = _transport(item)
            identity = _normalized_udid(_value(item, "serial", "SerialNumber", "UDID", "udid", "unique_device_id"))
            if transport is None or identity is None:
                continue
            name = _value(item, "name", "device_name", "DeviceName")
            model_name = _value(item, "model_name", "ProductType", "product_type")
            version = _value(item, "os_version", "ProductVersion", "product_version")
            row = {
                "id": identity,
                # usbmux usually does not expose a name.  Empty is an
                # explicit unknown value while preserving the stable shape
                # required by the macOS UI.
                "name": name if isinstance(name, str) else "",
                "modelName": model_name if isinstance(model_name, str) else None,
                "transport": transport,
                "osVersion": version if isinstance(version, str) else None,
            }
            selected.setdefault((identity, transport), row)
        return list(selected.values())

    def _usb_device_name(self, raw: list[Any], identity: str) -> str:
        """Best-effort read of the iPhone's own name over an existing pairing.

        usbmux rows carry no name.  An untrusted or locked phone simply keeps
        the empty unknown value; this never pairs and never fails the scan.
        """
        try:
            _, serial, connection = self._find_device(raw, identity, "usb")
            with tempfile.TemporaryDirectory(prefix="goflymac-name-") as temporary:
                client = self._open_lockdown(serial, connection, Path(temporary))
                try:
                    with quiet_dependencies():
                        name = _await(client.get_value(key="DeviceName"))
                finally:
                    with contextlib.suppress(Exception):
                        _await(getattr(client, "close")())
        except Exception:
            return ""
        return name if isinstance(name, str) and 0 < len(name) <= 200 else ""

    def devices(self) -> dict[str, Any]:
        raw = self._raw_devices()
        rows = self._device_rows(raw)
        names: dict[str, str] = {}
        for row in rows:
            if row["transport"] == "usb":
                names[row["id"]] = row["name"] or self._usb_device_name(raw, row["id"])
        for row in rows:
            if not row["name"]:
                row["name"] = names.get(row["id"], "")
        return {"devices": rows}

    def _teams(self) -> list[dict[str, Any]] | None:
        defaults = Path("/usr/bin/defaults")
        if not defaults.is_file():
            return None
        env = os.environ.copy()
        try:
            status, data = _safe_process([str(defaults), "export", "com.apple.dt.Xcode", "-"], env=env, timeout=20)
        except BridgeError:
            return None
        if status != 0:
            return None
        try:
            values = plistlib.loads(data)
        except Exception:
            return None
        if not isinstance(values, dict):
            return None
        groups = values.get("IDEProvisioningTeamByIdentifier", {})
        if not isinstance(groups, Mapping):
            return None
        found: dict[str, dict[str, Any]] = {}
        for group in groups.values():
            if not isinstance(group, list):
                continue
            for item in group:
                if not isinstance(item, Mapping):
                    continue
                team_id = item.get("teamID")
                if not isinstance(team_id, str) or TEAM_RE.fullmatch(team_id) is None:
                    continue
                name = item.get("teamName")
                if not isinstance(name, str) or not name or len(name) > 200:
                    name = f"Team {team_id}"
                free = item.get("isFreeProvisioningTeam") is True
                found.setdefault(team_id, {
                    "teamID": team_id,
                    "teamName": name,
                    "isFreeProvisioningTeam": free,
                })
        return sorted(found.values(), key=lambda team: (team["teamName"], team["teamID"]))

    def _project_identity(self) -> tuple[str | None, str | None]:
        path = self.config.resources_root / "iOSProject/GoFly.xcconfig"
        if path.is_symlink() or not path.is_file():
            return None, None
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            return None, None
        values: dict[str, str] = {}
        for line in text.splitlines():
            line = line.split("//", 1)[0].strip()
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
        version = values.get("MARKETING_VERSION")
        build = values.get("CURRENT_PROJECT_VERSION")
        if not isinstance(version, str) or re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", version) is None:
            version = None
        if not isinstance(build, str) or re.fullmatch(r"[0-9]{1,16}", build) is None:
            build = None
        return version, build

    def _check_xcode_installed(self) -> str:
        developer = self.config.developer_directory
        xcodebuild = developer / "usr/bin/xcodebuild"
        try:
            if developer.is_symlink() or not developer.is_dir():
                return "failed"
            if not xcodebuild.is_file():
                return "failed"
        except OSError:
            return "unknown"
        return "passed"

    def _xcode_minimum_macos_version(self, xcode_installed: bool) -> str | None:
        if not xcode_installed:
            return PLANNED_XCODE_MINIMUM_MACOS_VERSION
        info_path = self.config.developer_directory.parent / "Info.plist"
        if info_path.is_symlink() or not info_path.is_file():
            return None
        try:
            values = plistlib.loads(info_path.read_bytes())
        except (OSError, plistlib.InvalidFileException, ValueError):
            return None
        if not isinstance(values, Mapping):
            return None
        version = values.get("LSMinimumSystemVersion") or values.get("MinimumOSVersion")
        return version if _version_tuple(version) is not None else None

    def _available_space_kib(self) -> int | None:
        executable = Path("/bin/df")
        if not executable.is_file():
            return None
        try:
            status, data = _safe_process([str(executable), "-Pk", "/Applications"], timeout=15)
            if status != 0:
                return None
            lines = data.decode("utf-8", "strict").strip().splitlines()
        except (BridgeError, UnicodeDecodeError):
            return None
        if len(lines) < 2:
            return None
        fields = lines[-1].split()
        if len(fields) < 6 or re.fullmatch(r"[0-9]+", fields[3]) is None:
            return None
        return int(fields[3])

    def _check_first_launch(self, xcode_installed: bool) -> str:
        if not xcode_installed or not Path("/usr/bin/xcrun").is_file():
            return "unknown"
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(self.config.developer_directory)
        try:
            first_status, _ = _safe_process(
                ["/usr/bin/xcrun", "xcodebuild", "-checkFirstLaunchStatus"], env=env, timeout=30
            )
            if first_status != 0:
                return "failed"
            license_status, _ = _safe_process(
                ["/usr/bin/xcrun", "xcodebuild", "-license", "check"], env=env, timeout=30
            )
        except BridgeError:
            return "unknown"
        return "passed" if license_status == 0 else "failed"

    def _xcode_version(self) -> str | None:
        if not Path("/usr/bin/xcrun").is_file():
            return None
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(self.config.developer_directory)
        try:
            status, data = _safe_process(["/usr/bin/xcrun", "xcodebuild", "-version"], env=env, timeout=20)
        except BridgeError:
            return None
        if status != 0:
            return None
        try:
            first = data.decode("utf-8", "strict").splitlines()[0].strip()
        except (UnicodeDecodeError, IndexError):
            return None
        match = re.fullmatch(r"Xcode\s+([0-9][^\r\n]{0,40})", first)
        return match.group(1) if match else None

    def _ios_platform(self, xcode_installed: bool) -> tuple[str, str | None]:
        if not xcode_installed:
            return "unknown", None
        sdk_root = self.config.developer_directory / "Platforms/iPhoneOS.platform/Developer/SDKs"
        try:
            sdk_root.stat()
        except FileNotFoundError:
            return "failed", None
        except OSError:
            return "unknown", None
        if sdk_root.is_symlink() or not sdk_root.is_dir():
            return "unknown", None
        try:
            sdks = sorted(
                child.name[:-4]
                for child in sdk_root.iterdir()
                if child.name.startswith("iPhoneOS") and child.name.endswith(".sdk") and child.is_dir()
            )
        except OSError:
            return "unknown", None
        if not sdks:
            return "failed", None
        return "passed", sdks[-1]

    @staticmethod
    def _macos_version() -> str | None:
        executable = Path("/usr/bin/sw_vers")
        if not executable.is_file():
            return None
        try:
            status, data = _safe_process([str(executable), "-productVersion"], timeout=10)
        except BridgeError:
            return None
        if status != 0:
            return None
        try:
            value = data.decode("ascii", "strict").strip()
        except UnicodeDecodeError:
            return None
        return value if re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", value) else None

    def environment(self) -> dict[str, Any]:
        checks: list[dict[str, Any]] = []

        def check(identifier: str, title: str, detail: str, status: str) -> None:
            if status not in {"passed", "failed", "unknown"}:
                status = "unknown"
            checks.append({"id": identifier, "title": title, "detail": detail,
                           "status": status, "passed": status == "passed"})

        xcode_status = self._check_xcode_installed()
        xcode_installed = xcode_status == "passed"
        xcode = self._xcode_version() if xcode_installed else None
        macos = self._macos_version()
        minimum_macos = self._xcode_minimum_macos_version(xcode_installed)
        current_version = _version_tuple(macos)
        minimum_version = _version_tuple(minimum_macos)
        if current_version is None or minimum_version is None:
            macos_status = "unknown"
            macos_detail = "無法確認 macOS 版本與 Xcode 最低需求。"
        else:
            macos_status = "passed" if current_version >= minimum_version else "failed"
            macos_detail = f"macOS {macos}；Xcode 至少需要 macOS {minimum_macos}。"
        check("macos-version", "macOS 版本", macos_detail, macos_status)

        available_kib = self._available_space_kib()
        if available_kib is None:
            space_status = "unknown"
            space_detail = "無法確認可用儲存空間。"
        else:
            available_gb = available_kib / (1024 * 1024)
            space_status = "passed" if available_kib >= MINIMUM_FREE_SPACE_GB * 1024 * 1024 else "failed"
            space_detail = f"可用 {available_gb:.1f} GB；至少需要 {MINIMUM_FREE_SPACE_GB} GB。"
        check("available-space", "可用空間", space_detail, space_status)

        xcode_detail = (f"已偵測到 Xcode {xcode}。" if xcode else "已偵測到 Xcode，版本未知。") if xcode_installed else (
            "尚未偵測到 Xcode。" if xcode_status == "failed" else "無法確認 Xcode 是否已安裝。"
        )
        check("xcode-installed", "Xcode", xcode_detail, xcode_status)

        first_status = self._check_first_launch(xcode_installed)
        first_details = {
            "passed": "Xcode 初次啟動已完成，且已接受授權條款。",
            "failed": "請開啟 Xcode，完成初次啟動與授權條款。",
            "unknown": "無法確認 Xcode 初次啟動或授權條款狀態。",
        }
        check("xcode-first-launch", "Xcode 初次啟動", first_details[first_status], first_status)

        platform_status, sdk_name = self._ios_platform(xcode_installed)
        platform_details = {
            "passed": f"已安裝 iOS 平台 {sdk_name}。",
            "failed": "尚未下載 iOS 平台。",
            "unknown": "無法確認 iOS 平台狀態。",
        }
        check("ios-platform", "iOS 平台", platform_details[platform_status], platform_status)

        teams = self._teams() if xcode_installed else None
        team_status = "unknown" if teams is None else ("passed" if teams else "failed")
        team_details = {
            "passed": f"已找到 {len(teams or [])} 個 Apple 開發團隊。",
            "failed": "尚未在 Xcode 登入 Apple 開發者帳號。",
            "unknown": "無法確認 Xcode Apple 帳號狀態。",
        }
        check("apple-account", "Apple 帳號", team_details[team_status], team_status)

        ready = all(item["status"] == "passed" for item in checks)
        project_version, project_build = self._project_identity()
        return {"ready": ready, "checks": checks, "teams": teams or [], "xcodeVersion": xcode,
                "projectVersion": project_version, "projectBuild": project_build}

    def _profile_device_ids(self, team_id: str) -> list[str]:
        """Union of ProvisionedDevices across this team's Xcode-managed profiles.

        Free Personal Teams have no device page, so the local profiles are the
        only record of which phones hold the team's registration slots.
        """
        folders = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                   Path.home() / "Library/MobileDevice/Provisioning Profiles"]
        found: dict[str, None] = {}
        for folder in folders:
            try:
                if folder.is_symlink() or not folder.is_dir():
                    continue
                paths = sorted(folder.glob("*.mobileprovision"))[:200]
            except OSError:
                continue
            for path in paths:
                if path.is_symlink() or not path.is_file():
                    continue
                try:
                    status, data = _safe_process(["/usr/bin/security", "cms", "-D", "-i", str(path)], timeout=15)
                    profile = plistlib.loads(data) if status == 0 else None
                except Exception:
                    continue
                if not isinstance(profile, Mapping) or profile.get("TeamIdentifier") != [team_id]:
                    continue
                devices = profile.get("ProvisionedDevices")
                for device in devices if isinstance(devices, list) else []:
                    identity = _normalized_udid(device)
                    if identity is not None:
                        found.setdefault(identity, None)
        return list(found)

    def _xcode_device_names(self) -> dict[str, str]:
        """Best-effort names for phones Xcode has seen; empty when unavailable."""
        if not Path("/usr/bin/xcrun").is_file():
            return {}
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(self.config.developer_directory)
        with tempfile.TemporaryDirectory(prefix="goflymac-devicectl-") as temporary:
            output = Path(temporary) / "devices.json"
            try:
                status, _ = _safe_process(["/usr/bin/xcrun", "devicectl", "list", "devices",
                                           "--json-output", str(output)], env=env, timeout=30)
                values = json.loads(output.read_text(encoding="utf-8")) if status == 0 else None
            except Exception:
                return {}
        names: dict[str, str] = {}
        rows = values.get("result", {}).get("devices", []) if isinstance(values, Mapping) else []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, Mapping):
                continue
            hardware = row.get("hardwareProperties")
            properties = row.get("deviceProperties")
            identity = _normalized_udid(hardware.get("udid")) if isinstance(hardware, Mapping) else None
            name = properties.get("name") if isinstance(properties, Mapping) else None
            if identity is not None and isinstance(name, str) and 0 < len(name) <= 200:
                names[identity] = name
        return names

    def registered_devices(self, team_id: str) -> dict[str, Any]:
        identities = self._profile_device_ids(team_id)
        names = self._xcode_device_names() if identities else {}
        return {"devices": [{"id": identity, "name": names.get(identity, "")} for identity in identities]}

    def _find_device(self, raw: list[Any], target: str, selected_transport: str | None = None) -> tuple[Any, str, str]:
        matches: list[tuple[int, Any, str, str]] = []
        for item in raw:
            transport = _transport(item)
            serial = _value(item, "serial", "SerialNumber", "UDID", "udid", "unique_device_id")
            identity = _normalized_udid(serial)
            if transport is None or identity != target or (selected_transport is not None and transport != selected_transport):
                continue
            connection = _value(item, "connection_type", "ConnectionType", "connectionType")
            connection = connection.strip() if isinstance(connection, str) else (USB if transport == "usb" else NETWORK)
            matches.append((0 if transport == "usb" else 1, item, str(serial), connection))
        if not matches:
            raise BridgeError("device-disconnected")
        matches.sort(key=lambda item: item[0])
        _, item, serial, connection = matches[0]
        return item, serial, connection

    def _open_lockdown(self, serial: str, connection: str, cache: Path) -> Any:
        opener = getattr(self.device, "open_lockdown", None)
        if not callable(opener):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                return _await(opener(serial, connection, cache, autopair=False))
        except BridgeError:
            raise
        except Exception as error:
            raise BridgeError(_map_error(getattr(error, "code", "trust-required"))) from None

    def _read_values(self, client: Any, expected: str) -> dict[str, Any]:
        getter = getattr(client, "get_value", None)
        if not callable(getter):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                values = _await(getter())
        except Exception:
            raise BridgeError("trust-required") from None
        if not isinstance(values, Mapping):
            raise BridgeError("operation-failed")
        # Older lockdown variants may not expose DeveloperModeStatus.  That
        # is an unknown observation, not evidence that developer mode is off.
        developer_mode: bool | None = None
        try:
            with quiet_dependencies():
                developer_value = _await(getter(domain="com.apple.security.mac.amfi", key="DeveloperModeStatus"))
            if isinstance(developer_value, bool):
                developer_mode = developer_value
        except Exception:
            developer_mode = None
        actual = _normalized_udid(values.get("UniqueDeviceID"))
        if actual is None or actual != expected:
            raise BridgeError("identity-mismatch")
        version = values.get("ProductVersion")
        model_name = values.get("ProductType")
        return {
            "id": actual,
            "name": values.get("DeviceName") if isinstance(values.get("DeviceName"), str) else "",
            "modelName": model_name if isinstance(model_name, str) else None,
            "osVersion": version if isinstance(version, str) else None,
            "developerMode": developer_mode,
            "supportedOS": _version_supported(version),
        }

    def _installed_info(self, client: Any, *, bundle_id: str | None = None) -> tuple[bool | None, Mapping[str, Any] | None]:
        if not isinstance(bundle_id, str) or not bundle_id:
            raise BridgeError("invalid-request")
        try:
            from pymobiledevice3.services.installation_proxy import InstallationProxyService
        except Exception:
            return None, None
        service = None
        try:
            with quiet_dependencies():
                service = InstallationProxyService(client)
                apps = _await(service.get_apps(bundle_identifiers=[bundle_id]))
        except Exception:
            return None, None
        finally:
            if service is not None:
                with contextlib.suppress(Exception):
                    _await(service.close())
        if not isinstance(apps, Mapping):
            raise BridgeError("operation-failed")
        if bundle_id not in apps:
            return False, None
        target = apps[bundle_id]
        if not isinstance(target, Mapping):
            raise BridgeError("operation-failed")
        return True, target

    def inspect(self, target: str, bundle_id: str, selected_transport: str | None = None) -> dict[str, Any]:
        target = _normalized_udid(target) or (_ for _ in ()).throw(BridgeError("invalid-request"))
        raw = self._raw_devices()
        item, serial, connection = self._find_device(raw, target, selected_transport)
        with tempfile.TemporaryDirectory(prefix="goflymac-inspect-") as temporary:
            cache = Path(temporary)
            client = self._open_lockdown(serial, connection, cache)
            try:
                values = self._read_values(client, target)
                if not values["supportedOS"]:
                    raise BridgeError("unsupported-os")
                installed, info = self._installed_info(client, bundle_id=bundle_id)
                vpn_installed, _ = self._installed_info(client, bundle_id=LOCALDEVVPN_BUNDLE_ID)
            finally:
                with contextlib.suppress(Exception):
                    _await(getattr(client, "close")())
        raw_name = _value(item, "name", "device_name", "DeviceName")
        if not values["name"] and isinstance(raw_name, str):
            values["name"] = raw_name
        version = info.get("CFBundleShortVersionString") if isinstance(info, Mapping) else None
        build = info.get("CFBundleVersion") if isinstance(info, Mapping) else None
        if not isinstance(version, str):
            version = None
        if not isinstance(build, str):
            build = None
        return {
            "device": {
                "id": values["id"],
                "name": values["name"],
                "modelName": values["modelName"],
                "transport": "usb" if connection.upper() == USB else "wifi",
                "osVersion": values["osVersion"],
            },
            "developerMode": values["developerMode"],
            "installed": installed,
            "vpnInstalled": vpn_installed,
            "appVersion": version,
            "appBuild": build,
            "teamID": None,
            "expiresAt": None,
        }

    def handle(self, request: Any) -> dict[str, Any]:
        runner = _ACTIVE_RUNNER.get()
        if runner is not None:
            return self._handle(request)
        # Keep one event loop alive for every async dependency call in this
        # request.  In particular, a lockdown client must be opened, used,
        # and closed on the same loop.
        runner = _new_async_runner()
        token = _ACTIVE_RUNNER.set(runner)
        try:
            return self._handle(request)
        finally:
            _ACTIVE_RUNNER.reset(token)
            runner.close()

    def _handle(self, request: Any) -> dict[str, Any]:
        request_id = request.get("requestID") if isinstance(request, dict) else None
        try:
            action = _validate_request(request)
            if action == "environment":
                payload = self.environment()
            elif action == "devices":
                payload = self.devices()
            elif action == "registeredDevices":
                payload = self.registered_devices(request["teamID"])
            else:
                from Setup.setup_protocol import bundle_id_for_team
                payload = self.inspect(request["deviceID"], bundle_id_for_team(request["teamID"]), request.get("transport"))
            return wire_response(request, status="ok", payload=payload)
        except BridgeError as error:
            return wire_response(request, status="error", code=error.code)
        except Exception:
            return wire_response(request, status="error", code="operation-failed")


def _validate_request(request: Any) -> str:
    if not isinstance(request, dict):
        raise BridgeError("invalid-request")
    wire_request_id(request)
    action = wire_action(request)
    if action not in {"environment", "devices", "inspect", "registeredDevices"}:
        raise BridgeError("invalid-request")
    allowed = {"requestID", "action"}
    if action == "registeredDevices":
        allowed.add("teamID")
        team_id = request.get("teamID")
        if not isinstance(team_id, str) or TEAM_RE.fullmatch(team_id) is None:
            raise BridgeError("invalid-request")
    if action in {"inspect"}:
        allowed.update({"deviceID", "teamID"})
        target = request.get("deviceID")
        team_id = request.get("teamID")
        if _normalized_udid(target) is None or not isinstance(team_id, str) or TEAM_RE.fullmatch(team_id) is None:
            raise BridgeError("invalid-request")
        if "transport" in request:
            allowed.add("transport")
            if not isinstance(request["transport"], str) or request["transport"] not in {"usb", "wifi"}:
                raise BridgeError("invalid-request")
    if set(request) - allowed:
        raise BridgeError("invalid-request")
    return action


def _map_error(code: Any) -> str:
    mapping = {
        "no-usb-device": "device-disconnected",
        "target-device-not-found": "device-disconnected",
        "usb-device-list-failed": "operation-failed",
        "usb-lockdown-failed": "trust-required",
        "device-values-unavailable": "trust-required",
        "device-identity-unavailable": "identity-mismatch",
        "device-identity-mismatch": "identity-mismatch",
        "unsupported-os-version": "unsupported-os",
        "runtime-import-unavailable": "bundle-damaged",
        "runtime-version-mismatch": "dependency-mismatch",
    }
    mapped = mapping.get(str(code), "operation-failed")
    return mapped if mapped in SAFE_ERROR_CODES else "operation-failed"


def establish_process_group() -> None:
    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise BridgeError("environment-not-ready")


def _setup_error_payload(request: Any, config: Any = None) -> dict[str, Any]:
    if config is not None:
        try:
            from Setup.setup_journal import JournalStore, stages_for, uses_full_setup
        except ImportError:
            from setup_journal import JournalStore, stages_for, uses_full_setup
        try:
            journal = JournalStore(config.state_root).read()
            if isinstance(journal, dict) and (
                getattr(request, "setup_id", None) is None or journal.get("setupID") == request.setup_id
            ) and (
                getattr(request, "device_id", None) is None or journal.get("deviceID") == request.device_id
            ):
                stages = journal.get("stages", {})
                mode = journal.get("mode", "install")
                order = stages_for(journal)
                current, outcome = "complete", "confirmed"
                for stage in order:
                    state = stages.get(stage, {}).get("state")
                    if state in {"unknown", "inflight"}:
                        current, outcome = stage, "unknown"
                        break
                    if state != "confirmed":
                        current, outcome = stage, "inProgress"
                        break
                proof = journal.get("proof", {})
                if current == "complete" and outcome == "confirmed" and not (
                    proof.get("installationConfirmed") is True
                    and (not uses_full_setup(journal) or (
                        proof.get("pairingImported") is True and proof.get("supportObserved") is True
                    ))
                    and isinstance(journal.get("receiptSHA256"), str)
                    and re.fullmatch(r"[0-9a-f]{64}", journal["receiptSHA256"]) is not None
                ):
                    outcome = "unknown"
                payload: dict[str, Any] = {
                    "stage": current, "outcome": outcome,
                    "teamID": journal.get("intent", {}).get("teamID"),
                    "proof": {
                        "installationConfirmed": proof.get("installationConfirmed") is True,
                        "pairingImported": proof.get("pairingImported") is True,
                        "supportObserved": proof.get("supportObserved") is True,
                    },
                }
                artifact = journal.get("intent", {}).get("artifact")
                if isinstance(artifact, dict):
                    payload["app"] = {
                        "bundleID": artifact.get("bundleID"), "build": artifact.get("build"),
                        "profileSHA256": artifact.get("profileSHA256"),
                        "executableSHA256": artifact.get("executableSHA256"),
                    }
                    payload["expiresAt"] = artifact.get("expiresAt")
                receipt = journal.get("receiptSHA256")
                if isinstance(receipt, str) and re.fullmatch(r"[0-9a-f]{64}", receipt) is not None:
                    payload["receiptSHA256"] = receipt
                return payload
        except Exception:
            pass
    action = getattr(request, "action", None)
    stage = action if action in {"preflight", "artifact", "pairing", "install", "support", "handoff"} else "preflight"
    payload = {"stage": stage, "outcome": "unknown",
               "proof": {"installationConfirmed": False, "pairingImported": False, "supportObserved": False}}
    team_id = getattr(request, "team_id", None)
    if isinstance(team_id, str):
        payload["teamID"] = team_id
    return payload


def _setup_response(value: Mapping[str, Any], config: Config, *, producer_factory: Any = None) -> dict[str, Any]:
    try:
        from Setup.setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
        from Setup.setup_config import SetupConfiguration
        from Setup.setup_producer import SetupProducer
        from Setup.setup_protocol import bundle_id_for_team, decode_request
        from Setup.setup_support import PinnedSupportAdapter
    except ImportError:
        from setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
        from setup_config import SetupConfiguration
        from setup_producer import SetupProducer
        from setup_protocol import bundle_id_for_team, decode_request
        from setup_support import PinnedSupportAdapter
    bundle_config = config
    setup_config = None
    request = None
    try:
        request = decode_request(value)
        team_id = request.team_id
        if team_id is None:
            try:
                from Setup.setup_journal import JournalStore
            except ImportError:
                from setup_journal import JournalStore
            journal = JournalStore(bundle_config.state_root).read()
            if isinstance(journal, dict) and (
                request.setup_id is None or journal.get("setupID") == request.setup_id
            ) and (
                request.device_id is None or journal.get("deviceID") == request.device_id
            ):
                team_id = journal.get("intent", {}).get("teamID")
        target_bundle_id = bundle_id_for_team(team_id) if team_id is not None else None
        setup_config = SetupConfiguration.from_bundle(
            bundle_config.resources_root,
            bundle_config.developer_directory,
            target_bundle_id,
            bundle_config.target_name,
        )
        setup_config.validate_read_only_paths()
        if producer_factory is not None:
            producer = producer_factory(setup_config)
        else:
            device = PinnedPymobiledeviceAdapter(state_root=setup_config.state_root,
                                                 target_bundle_id=setup_config.target_bundle_id)
            producer = SetupProducer(setup_config, device=device, process=PinnedXcodeProcessAdapter(setup_config),
                                     support=PinnedSupportAdapter(device))
        payload = producer.handle(request).as_dict()
        from Setup.setup_protocol import _response_payload
        if request.action == "status" and request.setup_id is None:
            journal = JournalStore(setup_config.state_root).read()
            if isinstance(journal, dict):
                value = dict(value)
                value["setupID"] = journal.get("setupID")
                value["deviceID"] = journal.get("deviceID")
                value["mode"] = journal.get("mode", "install")
                value["transport"] = journal.get("intent", {}).get("transport", "usb")
                value["teamID"] = journal.get("intent", {}).get("teamID")
        return wire_response(value, status="ok", payload=_response_payload(payload))
    except WireError as error:
        return wire_response(value, status="error", code=error.code,
                             payload=_setup_error_payload(request, setup_config or bundle_config))
    except Exception:
        return wire_response(value, status="error", code="operation-failed",
                             payload=_setup_error_payload(request, setup_config or bundle_config))
    finally:
        try:
            close_async_runtime()
        except Exception:
            pass


def run_stdio(config: Config, *, stdin: Any = None, setup_producer_factory: Any = None,
              producer_factory: Any = None) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    setup_producer_factory = setup_producer_factory or producer_factory
    try:
        value = parse_object(read_request(stream))
        action = wire_action(value)
    except WireError as error:
        return wire_response(None, status="error", code=error.code)
    if action in {"environment", "devices", "inspect", "registeredDevices"}:
        try:
            _validate_request(value)
            return Bridge(config).handle(value)
        except WireError as error:
            return wire_response(value, status="error", code=error.code)
        except Exception:
            return wire_response(value, status="error", code="operation-failed")
    if action in {"preflight", "apply", "status"}:
        return _setup_response(value, config, producer_factory=setup_producer_factory)
    return wire_response(value, status="error", code="invalid-request")


def _emit(response: dict[str, Any], stream: Any = None) -> None:
    try:
        wire_emit(response, stream)
    except WireError:
        wire_emit(wire_response(None, status="error", code="operation-failed"), stream)


def main(argv: list[str] | None = None) -> int:
    # The Swift caller terminates the process group on cancellation.  Failure
    # to create a new group is harmless in an embedded test process.
    try:
        establish_process_group()
    except BridgeError as error:
        _emit(wire_response(None, status="error", code=error.code))
        return 1
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--resources", required=True)
    parser.add_argument("--developer-directory", required=True)
    parser.add_argument("--target-name", default=DEFAULT_TARGET_NAME)
    try:
        arguments, _ = parser.parse_known_args(argv)
    except SystemExit:
        return 2
    try:
        config = Config.from_bundle(
            arguments.resources,
            arguments.developer_directory,
            arguments.target_name,
        )
    except BridgeError as error:
        _emit(wire_response(None, status="error", code=error.code))
        return 0
    response = run_stdio(config)
    _emit(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
