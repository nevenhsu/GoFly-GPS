"""Write the GoFly IPA signature file (.ipa.sig) that GoFly Mac verifies.

Format and key rules: docs/MAC-INSTALLER-SPEC.md §5.5. The private key stays on
the maintainer's Mac (default ~/.ssh/gofly-ipa-signing.pem) and never enters
the repository. Signing uses OpenSSL 3+ (Ed25519 with -rawin); macOS LibreSSL
cannot do this, so Homebrew OpenSSL is preferred.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

SIGNATURE_FORMAT = "gofly-ipa-signature-v1"
# Must match the public key built into GoFly Mac (Bridge/Setup/ipa_store.py).
PUBLIC_KEY_B64 = "83Z/8TxN24aGZCX0jVLiPLdRrIA3+tVbUH5S1nnzY3c="
KEY_ID = "dacaa532bcd9b2e7"
DEFAULT_KEY = Path.home() / ".ssh" / "gofly-ipa-signing.pem"
DER_ED25519_PUBLIC_PREFIX = bytes.fromhex("302a300506032b6570032100")


def signed_message(key_id: str, sha256: str, version: str, build: str, protocol: int) -> bytes:
    return "".join(f"{part}\n" for part in (SIGNATURE_FORMAT, key_id, sha256, version, build, protocol)).encode("utf-8")


def find_openssl() -> str:
    candidates = [os.environ.get("GOFLY_OPENSSL"), "/opt/homebrew/bin/openssl", "/usr/local/bin/openssl",
                  shutil.which("openssl")]
    for candidate in candidates:
        if not candidate or not Path(candidate).is_file():
            continue
        try:
            version = subprocess.run([candidate, "version"], capture_output=True, text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        parts = version.split()
        if len(parts) >= 2 and parts[0] == "OpenSSL" and parts[1].split(".")[0].isdigit() and int(parts[1].split(".")[0]) >= 3:
            return candidate
    raise ValueError("OpenSSL 3 or newer is required to sign the IPA (brew install openssl).")


def _key_public_raw(openssl: str, key: Path) -> bytes:
    der = subprocess.run([openssl, "pkey", "-in", str(key), "-pubout", "-outform", "DER"],
                         capture_output=True, check=True).stdout
    if len(der) != 44 or not der.startswith(DER_ED25519_PUBLIC_PREFIX):
        raise ValueError("The signing key is not an Ed25519 key.")
    return der[-32:]


def ipa_identity(ipa: Path) -> tuple[str, str, int]:
    with zipfile.ZipFile(ipa) as bundle:
        info = plistlib.loads(bundle.read("Payload/GoFly.app/Info.plist"))
    version, build, protocol = info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"), info.get("GoFlyMacProtocol")
    if not isinstance(version, str) or not isinstance(build, str) or not version or not build:
        raise ValueError("The IPA has no version or build.")
    if not isinstance(protocol, int) or isinstance(protocol, bool) or protocol < 1:
        raise ValueError("The IPA has no integer GoFlyMacProtocol.")
    return version, build, protocol


def sign(ipa: Path, key: Path = DEFAULT_KEY) -> Path:
    if not key.is_file():
        raise ValueError(f"Signing key not found: {key}. Packaging refuses to publish an unsigned IPA.")
    openssl = find_openssl()
    public = _key_public_raw(openssl, key)
    if base64.b64encode(public).decode() != PUBLIC_KEY_B64 or hashlib.sha256(public).hexdigest()[:16] != KEY_ID:
        raise ValueError("The signing key does not match the public key built into GoFly Mac.")
    with ipa.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    version, build, protocol = ipa_identity(ipa)
    message = signed_message(KEY_ID, digest, version, build, protocol)
    with tempfile.TemporaryDirectory() as temporary:
        message_path, signature_path, public_path = (Path(temporary) / name for name in ("message", "signature", "public.pem"))
        message_path.write_bytes(message)
        subprocess.run([openssl, "pkeyutl", "-sign", "-inkey", str(key), "-rawin", "-in", str(message_path),
                        "-out", str(signature_path)], capture_output=True, check=True)
        subprocess.run([openssl, "pkey", "-in", str(key), "-pubout", "-out", str(public_path)], capture_output=True, check=True)
        subprocess.run([openssl, "pkeyutl", "-verify", "-pubin", "-inkey", str(public_path), "-rawin",
                        "-in", str(message_path), "-sigfile", str(signature_path)], capture_output=True, check=True)
        signature = signature_path.read_bytes()
    if len(signature) != 64:
        raise ValueError("Unexpected Ed25519 signature length.")
    document = {
        "format": SIGNATURE_FORMAT, "keyID": KEY_ID, "ipaSHA256": digest, "version": version,
        "build": build, "macProtocol": protocol, "signature": base64.b64encode(signature).decode(),
    }
    output = ipa.with_name(ipa.name + ".sig")
    output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--key", type=Path, default=Path(os.environ.get("GOFLY_IPA_SIGNING_KEY", DEFAULT_KEY)))
    arguments = parser.parse_args()
    try:
        print(sign(arguments.ipa, arguments.key))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Cannot sign IPA: {error}\n")
