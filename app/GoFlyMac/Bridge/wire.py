"""One strict JSON request/response wire for the GoFlyMac bridge."""

from __future__ import annotations

import json
import re
import sys
from typing import Any, Iterable, Mapping

MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\Z"
)
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
SAFE_ERROR_CODES = frozenset({
    "invalid-request", "protocol-mismatch", "configuration-invalid", "bundle-damaged", "dependency-mismatch",
    "runtime-api-mismatch", "environment-not-ready", "device-disconnected", "wifi-device-not-found",
    "wifi-pairing-unknown", "wifi-support-unavailable", "wifi-renew-unknown", "trust-required",
    "developer-mode-required", "unsupported-os", "identity-mismatch",
    "app-already-installed", "app-not-installed", "app-running",
    "signing-required", "signature-invalid", "artifact-mismatch", "support-unavailable",
    "pairing-unknown", "pairing-rejected", "handoff-unknown", "commit-unknown",
    "transaction-unknown", "transaction-conflict", "busy", "cancelled", "timeout",
    "storage-unavailable", "operation-failed", "usb-lockdown-failed", "usb-device-not-found",
    "device-identity-mismatch", "unsupported-os-version",
    "device-values-unavailable", "read-only-mode", "device-limit-reached",
})


class WireError(Exception):
    def __init__(self, code: str):
        self.code = code if code in SAFE_ERROR_CODES else "operation-failed"
        super().__init__(self.code)


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise WireError("invalid-request")
        result[key] = value
    return result


def parse_object(data: bytes) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > MAX_REQUEST_BYTES:
        raise WireError("invalid-request")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, WireError):
        raise WireError("invalid-request") from None
    if not isinstance(value, dict):
        raise WireError("invalid-request")
    return value


def read_request(stream: Any) -> bytes:
    reader = getattr(stream, "buffer", stream)
    try:
        data = reader.read(MAX_REQUEST_BYTES + 1)
    except Exception:
        raise WireError("invalid-request") from None
    if isinstance(data, str):
        data = data.encode("utf-8")
    if not isinstance(data, bytes) or len(data) > MAX_REQUEST_BYTES:
        raise WireError("invalid-request")
    return data


def request_id(value: Mapping[str, Any]) -> str:
    raw = value.get("requestID")
    if not isinstance(raw, str) or UUID_RE.fullmatch(raw) is None:
        raise WireError("invalid-request")
    return raw.lower()


def action(value: Mapping[str, Any]) -> str:
    raw = value.get("action")
    if not isinstance(raw, str) or not raw:
        raise WireError("invalid-request")
    return raw


def reject_unknown(value: Mapping[str, Any], allowed: Iterable[str]) -> None:
    if set(value) - set(allowed):
        raise WireError("invalid-request")


def response(request: Mapping[str, Any] | None, *, status: str, payload: Mapping[str, Any] | None = None,
             code: str | None = None) -> dict[str, Any]:
    value = request if isinstance(request, Mapping) else {}
    result: dict[str, Any] = {
        "requestID": value.get("requestID") if isinstance(value.get("requestID"), str) else None,
        "action": value.get("action") if isinstance(value.get("action"), str) else None,
        "status": status,
    }
    for key in ("setupID", "deviceID", "mode", "transport"):
        if isinstance(value.get(key), str):
            result[key] = value[key]
    if status == "error":
        result["code"] = code if code in SAFE_ERROR_CODES else "operation-failed"
    if payload is not None:
        result["payload"] = dict(payload)
    return result


def encode(value: Mapping[str, Any]) -> bytes:
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(data) > MAX_RESPONSE_BYTES:
        raise WireError("operation-failed")
    return data


def emit(value: Mapping[str, Any], stream: Any = None) -> None:
    output = stream if stream is not None else sys.stdout
    writer = getattr(output, "buffer", output)
    try:
        writer.write(encode(value) + b"\n")
        if hasattr(writer, "flush"):
            writer.flush()
    except TypeError:
        output.write(encode(value).decode("utf-8") + "\n")
