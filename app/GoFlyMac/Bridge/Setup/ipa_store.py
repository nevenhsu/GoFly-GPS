"""Signed GoFly IPA: verification, the saved copy, and GitHub Release lookup.

Rules: docs/MAC-INSTALLER-SPEC.md §5.5. Trust comes only from the built-in
Ed25519 public key; a URL or repository name only decides where bytes come from.
"""

from __future__ import annotations

import base64
import binascii
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import tempfile
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Mapping
from urllib.parse import urlsplit

try:
    from .setup_protocol import SetupBridgeError
except ImportError:  # script execution from the packaged Setup directory
    from setup_protocol import SetupBridgeError

SIGNATURE_FORMAT = "gofly-ipa-signature-v1"
PUBLIC_KEY_B64 = "83Z/8TxN24aGZCX0jVLiPLdRrIA3+tVbUH5S1nnzY3c="
KEY_ID = "dacaa532bcd9b2e7"
SUPPORTED_MAC_PROTOCOLS = frozenset({1})
BASE_BUNDLE_ID = "com.neven.gofly"
APP_ROOT = "Payload/GoFly.app/"
RELEASE_REPOSITORY = "nevenhsu/GoFly-GPS"
RELEASES_API = f"https://api.github.com/repos/{RELEASE_REPOSITORY}/releases?per_page=30"
IPA_NAME_RE = re.compile(r"GoFly-GPS-([0-9]+(?:\.[0-9]+){0,3})\.ipa\Z")
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){0,3}\Z")
BUILD_RE = re.compile(r"[0-9]{1,16}\Z")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
MAX_IPA_BYTES = 1024 * 1024 * 1024
MAX_UNPACKED_BYTES = 1024 * 1024 * 1024
MAX_SIGNATURE_BYTES = 8 * 1024
MAX_API_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 20000
HTTP_TIMEOUT = 30
IPA_NAME = "GoFly.ipa"
SIGNATURE_NAME = "GoFly.ipa.sig"
META_NAME = "meta.json"


@dataclass(frozen=True)
class IpaSignature:
    key_id: str
    sha256: str
    version: str
    build: str
    mac_protocol: int
    signature: bytes

    def message(self) -> bytes:
        parts = (SIGNATURE_FORMAT, self.key_id, self.sha256, self.version, self.build, str(self.mac_protocol))
        return "".join(f"{part}\n" for part in parts).encode("utf-8")


def version_key(version: str, build: str) -> tuple[tuple[int, ...], int]:
    """Order releases by marketing version, then build (builds restart per version)."""
    if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
        raise SetupBridgeError("ipa-invalid")
    if not isinstance(build, str) or BUILD_RE.fullmatch(build) is None:
        raise SetupBridgeError("ipa-invalid")
    numbers = tuple(int(part) for part in version.split("."))
    return numbers + (0,) * (4 - len(numbers)), int(build)


def parse_signature(data: bytes) -> IpaSignature:
    if not isinstance(data, bytes) or not data or len(data) > MAX_SIGNATURE_BYTES:
        raise SetupBridgeError("ipa-signature-invalid")
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise SetupBridgeError("ipa-signature-invalid") from None
    expected = {"format", "keyID", "ipaSHA256", "version", "build", "macProtocol", "signature"}
    if not isinstance(value, dict) or set(value) != expected or value["format"] != SIGNATURE_FORMAT:
        raise SetupBridgeError("ipa-signature-invalid")
    protocol = value["macProtocol"]
    if (
        not isinstance(value["keyID"], str)
        or not isinstance(value["ipaSHA256"], str) or SHA256_RE.fullmatch(value["ipaSHA256"]) is None
        or not isinstance(value["version"], str) or VERSION_RE.fullmatch(value["version"]) is None
        or not isinstance(value["build"], str) or BUILD_RE.fullmatch(value["build"]) is None
        or not isinstance(protocol, int) or isinstance(protocol, bool) or not 1 <= protocol <= 1_000_000
        or not isinstance(value["signature"], str)
    ):
        raise SetupBridgeError("ipa-signature-invalid")
    try:
        signature = base64.b64decode(value["signature"], validate=True)
    except (binascii.Error, ValueError):
        raise SetupBridgeError("ipa-signature-invalid") from None
    if len(signature) != 64:
        raise SetupBridgeError("ipa-signature-invalid")
    return IpaSignature(value["keyID"], value["ipaSHA256"], value["version"], value["build"], protocol, signature)


def verify_signature(signature: IpaSignature) -> None:
    """Raise unless the built-in GoFly key signed this manifest."""
    if signature.key_id != KEY_ID:
        raise SetupBridgeError("ipa-signature-invalid")
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError:
        raise SetupBridgeError("dependency-mismatch") from None
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(PUBLIC_KEY_B64))
    try:
        key.verify(signature.signature, signature.message())
    except InvalidSignature:
        raise SetupBridgeError("ipa-signature-invalid") from None


def file_sha256(path: Path, *, max_bytes: int = MAX_IPA_BYTES) -> str:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        raise SetupBridgeError("ipa-invalid") from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > max_bytes:
            raise SetupBridgeError("ipa-invalid")
        digest = hashlib.sha256()
        with os.fdopen(os.dup(fd), "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    finally:
        os.close(fd)


def _safe_member(name: str) -> bool:
    if not name or "\\" in name or name.startswith("/") or "\x00" in name:
        return False
    parts = PurePosixPath(name).parts
    if any(part in {"", ".", ".."} for part in parts):
        return False
    return name in {"Payload/", "Payload/GoFly.app/"} or name.startswith(APP_ROOT)


def _checked_members(bundle: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    members = bundle.infolist()
    if not members or len(members) > MAX_ENTRIES:
        raise SetupBridgeError("ipa-invalid")
    total = 0
    for member in members:
        mode = (member.external_attr >> 16) & 0xFFFF
        if not _safe_member(member.filename) or stat.S_ISLNK(mode) or member.flag_bits & 0x1:
            raise SetupBridgeError("ipa-invalid")
        relative = member.filename[len(APP_ROOT):] if member.filename.startswith(APP_ROOT) else ""
        # App extensions would need their own profiles; GoFly ships none (§5.5).
        if relative.startswith("PlugIns/") or relative.startswith("Extensions/"):
            raise SetupBridgeError("ipa-invalid")
        total += member.file_size
        if total > MAX_UNPACKED_BYTES:
            raise SetupBridgeError("ipa-invalid")
    return members


def inspect_ipa(ipa: Path, signature: IpaSignature) -> dict[str, Any]:
    """Verify signature, hash, archive shape and Info.plist; return metadata."""
    verify_signature(signature)
    if file_sha256(ipa) != signature.sha256:
        raise SetupBridgeError("ipa-signature-invalid")
    try:
        with zipfile.ZipFile(ipa) as bundle:
            _checked_members(bundle)
            info_member = bundle.getinfo(APP_ROOT + "Info.plist")
            if info_member.file_size > 1024 * 1024:
                raise SetupBridgeError("ipa-invalid")
            info = plistlib.loads(bundle.read(info_member))
            executable = info.get("CFBundleExecutable") if isinstance(info, dict) else None
            if executable != "GoFly":
                raise SetupBridgeError("ipa-invalid")
            bundle.getinfo(APP_ROOT + "GoFly")
    except SetupBridgeError:
        raise
    except (KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException, ValueError, EOFError):
        raise SetupBridgeError("ipa-invalid") from None
    protocol = info.get("GoFlyMacProtocol")
    if (
        info.get("CFBundleIdentifier") != BASE_BUNDLE_ID
        or info.get("CFBundleShortVersionString") != signature.version
        or info.get("CFBundleVersion") != signature.build
        or protocol != signature.mac_protocol
        or isinstance(protocol, bool)
    ):
        raise SetupBridgeError("ipa-invalid")
    if protocol not in SUPPORTED_MAC_PROTOCOLS:
        raise SetupBridgeError("ipa-protocol-unsupported")
    return {
        "version": signature.version, "build": signature.build,
        "macProtocol": signature.mac_protocol, "ipaSHA256": signature.sha256,
    }


def extract_app(ipa: Path, destination: Path, expected_sha256: str) -> Path:
    """Unpack Payload/GoFly.app into ``destination``/GoFly.app."""
    if file_sha256(ipa) != expected_sha256:
        raise SetupBridgeError("ipa-signature-invalid")
    app = destination / "GoFly.app"
    if app.exists() or app.is_symlink():
        raise SetupBridgeError("storage-unavailable")
    try:
        with zipfile.ZipFile(ipa) as bundle:
            for member in _checked_members(bundle):
                if not member.filename.startswith(APP_ROOT):
                    continue
                relative = member.filename[len(APP_ROOT):]
                target = app / relative if relative else app
                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True, mode=0o755)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                with bundle.open(member) as source, open(target, "xb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                mode = (member.external_attr >> 16) & 0o777
                os.chmod(target, 0o755 if mode & 0o111 or relative == "GoFly" else 0o644)
    except SetupBridgeError:
        raise
    except (OSError, zipfile.BadZipFile, ValueError, EOFError):
        raise SetupBridgeError("ipa-invalid") from None
    if not (app / "Info.plist").is_file() or not (app / "GoFly").is_file():
        raise SetupBridgeError("ipa-invalid")
    return app


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


class IpaStore:
    """The one saved IPA under state/ipa/current, replaced only by a verified file."""

    def __init__(self, state_root: Path):
        self.state_root = Path(state_root)
        self.root = self.state_root / "ipa"
        self.current_dir = self.root / "current"

    def _ensure_root(self) -> None:
        for path in (self.state_root.parent, self.state_root, self.root):
            if path.is_symlink() or (path.exists() and not path.is_dir()):
                raise SetupBridgeError("storage-unavailable")
            if not path.exists():
                path.mkdir(mode=0o700)
            os.chmod(path, 0o700)

    def _recover(self) -> None:
        """Finish or undo a swap interrupted between its two renames."""
        if not self.root.is_dir() or self.root.is_symlink():
            return
        previous = sorted(self.root.glob(".previous-*"), key=lambda path: path.stat().st_mtime, reverse=True)
        if not self.current_dir.exists() and previous:
            os.rename(previous[0], self.current_dir)
            previous = previous[1:]
        for stale in previous + list(self.root.glob(".staging-*")):
            if stale.is_dir() and not stale.is_symlink():
                shutil.rmtree(stale, ignore_errors=True)

    def current(self) -> dict[str, Any] | None:
        """Metadata of the saved IPA after re-verifying it, or None."""
        try:
            self._recover()
            directory = self.current_dir
            if directory.is_symlink() or not directory.is_dir():
                return None
            ipa, sig, meta = (directory / IPA_NAME, directory / SIGNATURE_NAME, directory / META_NAME)
            if any(path.is_symlink() or not path.is_file() for path in (ipa, sig, meta)):
                return None
            signature = parse_signature(sig.read_bytes())
            stored = json.loads(meta.read_text(encoding="utf-8"))
            if not isinstance(stored, dict) or stored.get("ipaSHA256") != signature.sha256:
                return None
            verify_signature(signature)
            if file_sha256(ipa) != signature.sha256:
                return None
            result = dict(stored)
            result.update(version=signature.version, build=signature.build,
                          macProtocol=signature.mac_protocol, ipaSHA256=signature.sha256,
                          supported=signature.mac_protocol in SUPPORTED_MAC_PROTOCOLS)
            return result
        except (SetupBridgeError, OSError, ValueError, UnicodeError):
            return None

    def ipa_path(self) -> Path:
        return self.current_dir / IPA_NAME

    def import_files(self, ipa: Path, signature_data: bytes, *, source: str, source_name: str,
                     minimum: tuple[str, str] | None = None) -> dict[str, Any]:
        """Verify, then atomically replace the saved IPA. A failure keeps the old one."""
        signature = parse_signature(signature_data)
        self._ensure_root()
        self._recover()
        staging = Path(tempfile.mkdtemp(prefix=".staging-", dir=self.root))
        try:
            os.chmod(staging, 0o700)
            staged_ipa = staging / IPA_NAME
            if ipa.is_symlink() or not ipa.is_file() or ipa.stat().st_size > MAX_IPA_BYTES:
                raise SetupBridgeError("ipa-invalid")
            shutil.copyfile(ipa, staged_ipa)
            (staging / SIGNATURE_NAME).write_bytes(signature_data)
            meta = inspect_ipa(staged_ipa, signature)
            if minimum is not None and version_key(meta["version"], meta["build"]) < version_key(*minimum):
                raise SetupBridgeError("ipa-downgrade")
            meta.update(source=source, sourceName=source_name[:300], importedAt=_now())
            (staging / META_NAME).write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
            previous = None
            if self.current_dir.exists():
                previous = self.root / f".previous-{uuid.uuid4().hex}"
                os.rename(self.current_dir, previous)
            os.rename(staging, self.current_dir)
            staging = None
            if previous is not None:
                shutil.rmtree(previous, ignore_errors=True)
            current = self.current()
            if current is None:
                raise SetupBridgeError("storage-unavailable")
            return current
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        finally:
            if staging is not None:
                shutil.rmtree(staging, ignore_errors=True)


# --- network -----------------------------------------------------------------

def _https(url: Any) -> str:
    if not isinstance(url, str) or len(url) > 2048:
        raise SetupBridgeError("invalid-request")
    parts = urlsplit(url)
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        raise SetupBridgeError("invalid-request")
    return url


def _session() -> Any:
    try:
        import requests
    except ImportError:
        raise SetupBridgeError("dependency-mismatch") from None
    session = requests.Session()
    session.headers["User-Agent"] = "GoFly-Mac"
    return session


def download(url: str, destination: Path, *, max_bytes: int, missing_code: str = "ipa-download-failed") -> None:
    """Stream an https URL into ``destination`` with a size cap."""
    _https(url)
    try:
        import requests
        session = _session()
        with session.get(url, stream=True, timeout=HTTP_TIMEOUT, allow_redirects=True) as reply:
            if urlsplit(reply.url).scheme != "https":
                raise SetupBridgeError("ipa-download-failed")
            if reply.status_code == 404:
                raise SetupBridgeError(missing_code)
            if reply.status_code != 200:
                raise SetupBridgeError("ipa-download-failed")
            size = 0
            with open(destination, "xb") as output:
                for chunk in reply.iter_content(1024 * 1024):
                    size += len(chunk)
                    if size > max_bytes:
                        raise SetupBridgeError("ipa-download-failed" if max_bytes > MAX_SIGNATURE_BYTES
                                               else "ipa-signature-invalid")
                    output.write(chunk)
    except SetupBridgeError:
        raise
    except (OSError, requests.RequestException):
        raise SetupBridgeError("ipa-download-failed") from None


def _api_json(url: str) -> Any:
    try:
        import requests
        with _session().get(url, timeout=HTTP_TIMEOUT, headers={"Accept": "application/vnd.github+json"},
                            stream=True) as reply:
            if reply.status_code != 200:
                raise SetupBridgeError("release-unavailable")
            data = reply.raw.read(MAX_API_BYTES + 1, decode_content=True)
    except SetupBridgeError:
        raise
    except (OSError, requests.RequestException):
        raise SetupBridgeError("release-unavailable") from None
    if len(data) > MAX_API_BYTES:
        raise SetupBridgeError("release-unavailable")
    try:
        return json.loads(data)
    except ValueError:
        raise SetupBridgeError("release-unavailable") from None


def release_info(version: str | None = None) -> dict[str, Any]:
    """Newest published Release that has a GoFly IPA and its .sig (or one version)."""
    if version is not None and VERSION_RE.fullmatch(version) is None:
        raise SetupBridgeError("invalid-request")
    releases = _api_json(RELEASES_API)
    if not isinstance(releases, list):
        raise SetupBridgeError("release-unavailable")
    for release in releases:
        if not isinstance(release, dict) or release.get("draft") or release.get("prerelease"):
            continue
        assets = {asset.get("name"): asset for asset in release.get("assets") or [] if isinstance(asset, dict)}
        for name, asset in assets.items():
            match = IPA_NAME_RE.fullmatch(name) if isinstance(name, str) else None
            if match is None or (version is not None and match.group(1) != version):
                continue
            sig_asset = assets.get(name + ".sig")
            ipa_url, sig_url = asset.get("browser_download_url"), (sig_asset or {}).get("browser_download_url")
            if not isinstance(ipa_url, str) or not isinstance(sig_url, str):
                continue
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "release.sig"
                download(_https(sig_url), path, max_bytes=MAX_SIGNATURE_BYTES, missing_code="ipa-signature-missing")
                data = path.read_bytes()
            signature = parse_signature(data)
            verify_signature(signature)
            if signature.version != match.group(1):
                continue
            size = asset.get("size")
            return {
                "version": signature.version, "build": signature.build, "macProtocol": signature.mac_protocol,
                "supported": signature.mac_protocol in SUPPORTED_MAC_PROTOCOLS,
                "ipaURL": _https(ipa_url), "sigURL": _https(sig_url), "fileName": name,
                "size": size if isinstance(size, int) else None,
                "publishedAt": release.get("published_at") if isinstance(release.get("published_at"), str) else None,
            }
    raise SetupBridgeError("release-unavailable")


def import_from_sources(store: IpaStore, *, ipa_url: str | None = None, ipa_path: str | None = None,
                        sig_url: str | None = None, sig_path: str | None = None,
                        minimum: tuple[str, str] | None = None) -> dict[str, Any]:
    """Fetch or read the IPA and its signature, then verify and save them."""
    if (ipa_url is None) == (ipa_path is None) or (sig_url is not None and sig_path is not None):
        raise SetupBridgeError("invalid-request")
    with tempfile.TemporaryDirectory(prefix="gofly-ipa-") as temporary:
        work = Path(temporary)
        if sig_path is not None:
            candidate = Path(sig_path)
            if not candidate.is_absolute() or candidate.is_symlink() or not candidate.is_file():
                raise SetupBridgeError("ipa-signature-missing")
            if candidate.stat().st_size > MAX_SIGNATURE_BYTES:
                raise SetupBridgeError("ipa-signature-invalid")
            signature_data = candidate.read_bytes()
        else:
            if sig_url is None:
                if ipa_url is None:
                    raise SetupBridgeError("ipa-signature-missing")
                sig_url = ipa_url + ".sig" if not urlsplit(ipa_url).query else None
                if sig_url is None:
                    raise SetupBridgeError("ipa-signature-missing")
            download(_https(sig_url), work / "download.sig", max_bytes=MAX_SIGNATURE_BYTES,
                     missing_code="ipa-signature-missing")
            signature_data = (work / "download.sig").read_bytes()
        # Check the signature itself before spending time on a large download.
        verify_signature(parse_signature(signature_data))
        if ipa_url is not None:
            ipa = work / "download.ipa"
            download(_https(ipa_url), ipa, max_bytes=MAX_IPA_BYTES)
            source, name = "url", ipa_url
        else:
            ipa = Path(ipa_path)
            if not ipa.is_absolute() or ipa.suffix != ".ipa" or ipa.is_symlink() or not ipa.is_file():
                raise SetupBridgeError("ipa-invalid")
            source, name = "file", ipa.name
        return store.import_files(ipa, signature_data, source=source, source_name=name, minimum=minimum)
