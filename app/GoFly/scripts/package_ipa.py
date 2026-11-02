"""Package an unsigned device build for SideStore without changing the Mac build."""

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import zipfile


def package(app: Path, output_directory: Path) -> Path:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("GoFlyRequiresMacSetup") is not True:
        raise ValueError("The source app must require Mac setup (Boolean true).")
    if info.get("CFBundleIdentifier") != "com.neven.gofly":
        raise ValueError("Build the unsigned IPA with the base GoFly bundle ID.")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("An iPhoneOS device build is required.")
    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not version or any(c not in "0123456789." for c in version):
        raise ValueError("Invalid GoFly release version.")
    executable = info.get("CFBundleExecutable")
    if executable != "GoFly" or not (app / executable).is_file():
        raise ValueError("Missing GoFly executable.")
    if info.get("BGTaskSchedulerPermittedIdentifiers") != ["com.neven.gofly.movement"]:
        raise ValueError("Background task identifier does not match the IPA bundle ID.")
    for path in app.rglob("*"):
        if path.is_symlink() or path.name in {"embedded.mobileprovision", "_CodeSignature"}:
            raise ValueError("Use an unsigned build without profiles, signatures, or symlinks.")

    output_directory.mkdir(parents=True, exist_ok=True)
    output = output_directory / f"GoFly-GPS-{version}.ipa"
    checksum = output.with_suffix(".ipa.sha256")
    with tempfile.TemporaryDirectory(prefix=".sidestore-", dir=output_directory) as temporary:
        root = Path(temporary)
        staged = root / "Payload" / "GoFly.app"
        shutil.copytree(app, staged)
        # The production source remains Mac-gated. Only this unsigned copy is
        # changed; SideStore signs the final payload with the user's account.
        info["GoFlyRequiresMacSetup"] = False
        (staged / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        archive = root / output.name
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(staged.rglob("*")):
                bundle.write(path, path.relative_to(root))
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                raise ValueError("IPA integrity verification failed.")
            packaged = plistlib.loads(bundle.read("Payload/GoFly.app/Info.plist"))
            if packaged != info or packaged["GoFlyRequiresMacSetup"] is not False:
                raise ValueError("IPA startup policy verification failed.")
        with archive.open("rb") as handle:
            digest = hashlib.file_digest(handle, "sha256").hexdigest()
        # Publish only a complete, verified archive. An earlier build of the
        # same version moves to archive/<UTC time>/ instead of being replaced.
        archive_existing(output, checksum, output_directory)
        os.link(archive, output)
        checksum.write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    return output


def archive_existing(output: Path, checksum: Path, output_directory: Path) -> None:
    existing = [path for path in (output, checksum) if path.exists() or path.is_symlink()]
    if not existing:
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    destination = output_directory / "archive" / stamp
    destination.mkdir(parents=True)
    for path in existing:
        os.rename(path, destination / path.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        print(package(arguments.app, arguments.output_directory))
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Cannot package SideStore IPA: {error}\n")
