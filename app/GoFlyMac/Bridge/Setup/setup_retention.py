"""Best-effort archived setup retention; caller must hold operation.lock."""

from __future__ import annotations

import contextlib
from collections import deque
import hashlib
import json
import logging
import os
import re
import stat
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    from .setup_journal import (
        JournalStore, MAX_JOURNAL_BYTES, _pairs, _read_regular_bytes, _regular,
        _validate_private_dir, _validate_setup_id, stages_for, uses_full_setup, uses_wifi_renew,
    )
    from .setup_protocol import SetupBridgeError
except ImportError:  # script execution from the packaged Setup directory
    from setup_journal import (
        JournalStore, MAX_JOURNAL_BYTES, _pairs, _read_regular_bytes, _regular,
        _validate_private_dir, _validate_setup_id, stages_for, uses_full_setup, uses_wifi_renew,
    )
    from setup_protocol import SetupBridgeError

RETAIN_TRANSACTIONS = 10
RETAIN_DAYS = 90
RETAIN_LOG_LINES = 1000
_LARGE_PATHS = ("build", "artifact", "support", "support.actual")
# Mac-local fetch staging left by an interrupted support preparation; once the
# transaction is archived nothing resumes it, so it is a reclaimable product.
_SUPPORT_STAGING = re.compile(r"\.support(?:\.actual)?\.[0-9a-f]{24}\.staging")
_ARCHIVES = ("journal.completed.json", "journal.abandoned.json")
_SMALL_PATHS = ("pairing.candidate", *_ARCHIVES, "pruned.json", "xcodebuild-error.txt")
_LOG = logging.getLogger(__name__)


def _sync(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _atomic(path: Path, data: bytes) -> None:
    _regular(path, allow_missing=True)
    fd, name = tempfile.mkstemp(prefix=".retention-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        _regular(path, allow_missing=True)
        os.replace(temporary, path)
        _sync(path.parent)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temporary.unlink()


def _parse(raw: bytes) -> Any:
    return json.loads(raw, object_pairs_hook=_pairs, parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()))


def _json(path: Path) -> Any:
    return _parse(_read_regular_bytes(path, max_bytes=MAX_JOURNAL_BYTES))


def _save(path: Path, value: Any) -> None:
    data = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    if len(data) > MAX_JOURNAL_BYTES:
        raise SetupBridgeError("storage-unavailable")
    _atomic(path, data)


def _handoff(name: str) -> bool:
    return "incoming.plist" in name or ".consuming" in name


def _large(name: str) -> bool:
    return name in _LARGE_PATHS or _SUPPORT_STAGING.fullmatch(name) is not None


def _logged(line: bytes, record: dict[str, Any]) -> bool:
    try:
        value = json.loads(line)
    except ValueError:
        return False
    return isinstance(value, dict) and all(value.get(key) == record[key] for key in ("setupID", "result"))


def _append(root: Path, record: dict[str, Any], *, once: bool = False) -> None:
    path = root / "retention-log.jsonl"
    _regular(path, allow_missing=True)
    lines = []
    if path.exists():
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as handle:
            lines = list(deque(handle, maxlen=RETAIN_LOG_LINES - 1))
        lines = [line.rstrip(b"\n") for line in lines]
    # Repeated skips must not rotate deletion summaries out of the bounded log.
    if once and any(_logged(line, record) for line in lines):
        return
    lines.append(json.dumps(dict(record, time=time.time()), sort_keys=True).encode())
    _atomic(path, b"\n".join(lines[-RETAIN_LOG_LINES:]) + b"\n")


def _report(root: Path, setup_id: str | None, result: str) -> None:
    try:
        _append(root, {"setupID": setup_id, "result": result}, once=True)
    except Exception:
        # A full/unavailable disk must not change the successful install result.
        _LOG.warning("Setup retention could not record %s (%s)", result, setup_id)


def _tree_safe(path: Path) -> None:
    info = path.lstat()
    if info.st_uid != os.getuid():
        raise SetupBridgeError("storage-unavailable")
    if stat.S_ISDIR(info.st_mode):
        for child in path.iterdir():
            if _handoff(child.name):
                raise SetupBridgeError("storage-unavailable")
            _tree_safe(child)
    elif not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise SetupBridgeError("storage-unavailable")


def _remove_contents(fd: int) -> None:
    for name in os.listdir(fd):
        if _handoff(name):
            raise SetupBridgeError("storage-unavailable")
        info = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if info.st_uid != os.getuid():
            raise SetupBridgeError("storage-unavailable")
        if stat.S_ISDIR(info.st_mode):
            child_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                _remove_contents(child_fd)
            finally:
                os.close(child_fd)
            os.rmdir(name, dir_fd=fd)
        elif stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
            os.unlink(name, dir_fd=fd)
        else:
            raise SetupBridgeError("storage-unavailable")
    os.fsync(fd)


def _remove_tree(path: Path) -> None:
    """Use no-follow directory descriptors even after the safety inventory."""
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        _remove_contents(fd)
    finally:
        os.close(fd)
    path.rmdir()
    _sync(path.parent)


def _inventory(path: Path, *, deleting: bool = False) -> None:
    _validate_private_dir(path)
    for child in path.iterdir():
        if _large(child.name):
            if not stat.S_ISDIR(child.lstat().st_mode):
                raise SetupBridgeError("storage-unavailable")
            _tree_safe(child)
        elif child.name in _SMALL_PATHS:
            _regular(child)
        elif _handoff(child.name) or ".staging" in child.name:
            raise SetupBridgeError("storage-unavailable")
        elif deleting:
            # Whole-transaction deletion never guesses at unknown contents.
            raise SetupBridgeError("storage-unavailable")
        else:
            _tree_safe(child)


def _archive(path: Path) -> dict[str, Any]:
    archives = [path / name for name in _ARCHIVES if (path / name).exists() or (path / name).is_symlink()]
    if len(archives) != 1:
        raise SetupBridgeError("storage-unavailable")
    archive = archives[0]
    raw = _read_regular_bytes(archive, max_bytes=MAX_JOURNAL_BYTES)
    journal = _parse(raw)
    JournalStore._validate(journal)
    if journal["setupID"] != path.name:
        raise SetupBridgeError("storage-unavailable")
    completed = archive.name == "journal.completed.json"
    if completed:
        proof_keys = ("installationConfirmed", "pairingImported", "supportObserved") if uses_full_setup(journal) or uses_wifi_renew(journal) else ("installationConfirmed",)
        receipt = dict(journal)
        digest = receipt.pop("receiptSHA256", None)
        if (
            any(journal["stages"][stage]["state"] != "confirmed" for stage in stages_for(journal))
            or any(journal["proof"][key] is not True for key in proof_keys)
            or digest != hashlib.sha256(json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        ):
            raise SetupBridgeError("storage-unavailable")
    birth = getattr(path.stat(), "st_birthtime", None)
    candidate = path / "pairing.candidate"
    pairing_sha = hashlib.sha256(_read_regular_bytes(candidate, max_bytes=1024 * 1024)).hexdigest() if candidate.exists() else None
    return {
        "setupID": journal["setupID"], "deviceID": journal["deviceID"],
        "mode": journal.get("mode", "install"), "completed": completed,
        "createdAt": birth, "archivedAt": archive.stat().st_mtime,
        "pairingSHA256": pairing_sha,
        "archiveName": archive.name,
        "archiveSHA256": hashlib.sha256(raw).hexdigest(),
    }


def _prune(root: Path, path: Path) -> None:
    prior = path / "pruned.json"
    value = _json(prior) if prior.exists() else {"paths": [], "pending": []}
    if not isinstance(value, dict):
        raise SetupBridgeError("storage-unavailable")
    removed, pending = value.get("paths"), value.get("pending", [])
    if any(not isinstance(names, list) or any(not _large(name) for name in names) for names in (removed, pending)):
        raise SetupBridgeError("storage-unavailable")
    for name in sorted({*_LARGE_PATHS, *pending, *filter(_large, os.listdir(path))}):
        target = path / name
        if not target.exists() and name not in pending:
            continue
        try:
            # Record intent before unlink so a failed evidence write can recover.
            pending = sorted(set(pending + [name]))
            _save(prior, {"time": time.time(), "paths": removed, "pending": pending})
            if target.exists():
                _remove_tree(target)
            removed = sorted(set(removed + [name]))
            pending.remove(name)
            _save(prior, {"time": time.time(), "paths": removed, "pending": pending})
        except Exception:
            _report(root, path.name, "prune-failed:" + name)


def _delete(path: Path, record: dict[str, Any]) -> None:
    _inventory(path, deleting=True)
    archive = path / record["archiveName"]
    other = "journal.abandoned.json" if record["archiveName"] == "journal.completed.json" else "journal.completed.json"
    if (path / other).exists():
        raise SetupBridgeError("storage-unavailable")
    if archive.exists() and hashlib.sha256(_read_regular_bytes(archive, max_bytes=MAX_JOURNAL_BYTES)).hexdigest() != record["archiveSHA256"]:
        raise SetupBridgeError("storage-unavailable")
    pairing = path / "pairing.candidate"
    if pairing.exists() and hashlib.sha256(_read_regular_bytes(pairing, max_bytes=1024 * 1024)).hexdigest() != record["pairingSHA256"]:
        raise SetupBridgeError("storage-unavailable")
    for name in sorted(filter(_large, os.listdir(path))):
        _remove_tree(path / name)
    for name in _SMALL_PATHS:
        target = path / name
        _regular(target, allow_missing=True)
        if target.exists():
            target.unlink()
            _sync(path)
    path.rmdir()
    _sync(path.parent)


def _run(store: JournalStore, now: float) -> None:
    current = store.read()
    if current is None:
        return
    transactions = store.root / "transactions"
    _validate_private_dir(transactions)
    protected = {current["setupID"], current["intent"].get("pairingSourceSetupID")}
    records = []
    # Read all archives before pruning so each device's newest success is protected.
    for path in transactions.iterdir():
        if path.name.startswith(".deleting-"):
            continue
        try:
            if _validate_setup_id(path.name) != path.name:
                raise SetupBridgeError("storage-unavailable")
            _validate_private_dir(path)
            if path.name == current["setupID"]:
                continue
            record = _archive(path)
            records.append(record)
        except Exception:
            protected.add(path.name)
            _report(store.root, path.name, "skipped-unknown-archive")
    records.sort(key=lambda record: (record["archivedAt"], record["setupID"]), reverse=True)
    devices = set()
    for record in records:
        if record["completed"] and record["deviceID"] not in devices:
            protected.add(record["setupID"])
            devices.add(record["deviceID"])
    eligible = []
    for record in records:
        path = transactions / record["setupID"]
        if path.name in protected:
            continue
        try:
            _inventory(path)
            _prune(store.root, path)
            try:
                _inventory(path, deleting=True)
                eligible.append(record)
            except Exception:
                protected.add(path.name)
                _report(store.root, path.name, "skipped-unknown-contents")
        except Exception:
            _report(store.root, path.name, "skipped-unsafe-contents")

    # A separate durable intent survives log rotation and even an empty tombstone.
    pending_path = store.root / "retention-pending.json"
    _regular(pending_path, allow_missing=True)
    pending = _json(pending_path) if pending_path.exists() else {}
    if not isinstance(pending, dict):
        raise SetupBridgeError("storage-unavailable")
    def finish(setup_id: str, record: dict[str, Any]) -> None:
        try:
            if _validate_setup_id(setup_id) != setup_id or record["setupID"] != setup_id or record["archiveName"] not in _ARCHIVES:
                raise SetupBridgeError("storage-unavailable")
            if setup_id in protected:
                return
            target = transactions / (".deleting-" + setup_id)
            if target.exists() or target.is_symlink():
                _delete(target, record)
                _append(store.root, dict(record, result="deleted"))
            del pending[setup_id]
            _save(pending_path, pending)
        except Exception:
            _report(store.root, setup_id, "delete-failed")

    for setup_id, record in list(pending.items()):
        finish(setup_id, record)
    for record in eligible[RETAIN_TRANSACTIONS:]:
        if record["archivedAt"] >= now - RETAIN_DAYS * 86400:
            continue
        setup_id = record["setupID"]
        try:
            source = transactions / setup_id
            target = transactions / (".deleting-" + setup_id)
            if target.exists() or target.is_symlink():
                raise SetupBridgeError("storage-unavailable")
            _append(store.root, dict(record, result="deleting"))
            pending[setup_id] = record
            _save(pending_path, pending)
            source.rename(target)
            _sync(transactions)
            finish(setup_id, record)
        except Exception:
            _report(store.root, setup_id, "delete-prepare-failed")
            # Discard uncommitted in-memory intent; retain any durable rename intent.
            pending = _json(pending_path) if pending_path.exists() else {}
    for path in transactions.iterdir():
        if path.name.startswith(".deleting-") and path.name[10:] not in pending:
            _report(store.root, path.name, "skipped-unknown-deletion")


def retain_archives_locked(store: JournalStore, *, now: float | None = None) -> None:
    """RET-1/3 then RET-6, without changing a confirmed installation result."""
    try:
        _run(store, time.time() if now is None else now)
    except Exception:
        _report(store.root, None, "retention-failed")
