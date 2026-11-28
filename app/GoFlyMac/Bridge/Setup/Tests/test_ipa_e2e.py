"""Local end-to-end check of the IPA install path with a simulated iPhone.

Real: IPA signature verification, the saved IPA store, the bridge ipaImport
action, xcodebuild of the signing stub, re-signing, the strict artifact
validator and the setup producer's install and renew transactions.
Simulated: the iPhone (no USB device is needed and none is contacted).
Apple is not contacted either: provisioning updates stay off, so the Mac must
already hold a profile for com.neven.gofly.<teamid> (any earlier GoFly install).

Needs the maintainer's signing key, Xcode and that profile; otherwise skipped.
Run: work/mac-setup-env/bin/python -m unittest Setup.Tests.test_ipa_e2e  (from Bridge/)
"""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_ROOT = PACKAGE_ROOT.parent
WORKSPACE = BRIDGE_ROOT.parents[2]
sys.path.append(str(PACKAGE_ROOT))
sys.path.append(str(BRIDGE_ROOT))

import bridge  # noqa: E402
import ipa_store  # noqa: E402
from ipa_resign import IpaResignProcessAdapter  # noqa: E402
from setup_adapters import (  # noqa: E402
    ArtifactIdentity, DeviceObservation, FormalArtifactValidator, InstalledAppObservation,
    PairingObservation, xcode_team_is_free,
)
from setup_config import SetupConfiguration  # noqa: E402
from setup_producer import SetupProducer  # noqa: E402
from setup_protocol import SetupBridgeError, bundle_id_for_team, decode_request  # noqa: E402

DEVELOPER = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
SIGNING_KEY = Path(os.environ.get("GOFLY_IPA_SIGNING_KEY", Path.home() / ".ssh" / "gofly-ipa-signing.pem"))
SOURCE_IPA_DIR = WORKSPACE / "work" / "dist" / "ipa"
SIGN_SCRIPT = WORKSPACE / "app" / "GoFly" / "scripts" / "sign_ipa.py"


def _team_id() -> str | None:
    try:
        out = subprocess.run(["/usr/bin/defaults", "export", "com.apple.dt.Xcode", "-"],
                             capture_output=True, check=True).stdout
        groups = plistlib.loads(out).get("IDEProvisioningTeamByIdentifier", {})
    except Exception:
        return None
    teams = {item.get("teamID") for group in groups.values() for item in group if isinstance(item, dict)}
    teams.discard(None)
    return next(iter(teams)) if len(teams) == 1 else os.environ.get("GOFLY_TEAM_ID")


def _profile_device(team_id: str) -> str | None:
    """A UDID already in the local profile for the Team's GoFly bundle ID."""
    target = f"{team_id}.{bundle_id_for_team(team_id)}"
    folder = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    for path in sorted(folder.glob("*.mobileprovision")) if folder.is_dir() else []:
        data = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", str(path)], capture_output=True).stdout
        try:
            profile = plistlib.loads(data)
        except Exception:
            continue
        if profile.get("Entitlements", {}).get("application-identifier") == target and profile.get("ProvisionedDevices"):
            return profile["ProvisionedDevices"][0]
    return None


def _source_ipa() -> Path | None:
    candidates = sorted(SOURCE_IPA_DIR.glob("GoFly-GPS-*.ipa")) if SOURCE_IPA_DIR.is_dir() else []
    return candidates[-1] if candidates else None


def make_signed_ipa(source: Path, folder: Path, *, version: str | None = None, build: str | None = None) -> Path:
    """Copy a real GoFly IPA, ensure GoFlyMacProtocol (and optional version), sign it."""
    with zipfile.ZipFile(source) as original:
        info = plistlib.loads(original.read("Payload/GoFly.app/Info.plist"))
        version = version or info["CFBundleShortVersionString"]
        target = folder / f"GoFly-GPS-{version}.ipa"
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as copy:
            for item in original.infolist():
                data = original.read(item)
                if item.filename == "Payload/GoFly.app/Info.plist":
                    info["GoFlyMacProtocol"] = 1
                    info["CFBundleShortVersionString"] = version
                    if build is not None:
                        info["CFBundleVersion"] = build
                    data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
                copy.writestr(item, data)
    subprocess.run([sys.executable, str(SIGN_SCRIPT), str(target), "--key", str(SIGNING_KEY)],
                   check=True, capture_output=True)
    return target


class SimulatedPhone:
    """An attached, trusted iPhone in Developer Mode, entirely in memory."""

    def __init__(self, device_id: str, bundle_id: str) -> None:
        self.device_id = device_id
        self.bundle_id = bundle_id
        self.installed_build: str | None = None
        self.installed_apps: list[Path] = []

    def observe(self, device_id: str, *_args: object) -> DeviceObservation:
        return DeviceObservation(device_id, "26.4", "USB", True, True)

    def installed(self, device_id: str, *_args: object) -> InstalledAppObservation:
        return InstalledAppObservation(self.installed_build is not None, self.bundle_id, build=self.installed_build)

    def install(self, device_id: str, artifact: ArtifactIdentity, *_args: object) -> InstalledAppObservation:
        app = Path(artifact.path)
        self.installed_apps.append(app)
        self.installed_build = artifact.build
        return InstalledAppObservation(True, self.bundle_id, build=artifact.build)

    def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
        candidate.write_bytes(b"simulated pairing record")
        candidate.chmod(0o600)

    def pair(self, *_args: object) -> PairingObservation:
        return PairingObservation("verified", self.device_id, "d" * 64)

    def verify_pairing(self, *_args: object) -> PairingObservation:
        return PairingObservation("verified", self.device_id, "d" * 64)

    def retire_pending_pairing(self, *_args: object) -> None:
        """The simulated phone never holds an unclaimed pairing envelope."""


@unittest.skipUnless(SIGNING_KEY.is_file() and (DEVELOPER / "usr/bin/xcodebuild").is_file() and _source_ipa(),
                     "needs the IPA signing key, Xcode and a packaged IPA in work/dist/ipa")
class IpaInstallEndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.team_id = _team_id()
        cls.device_id = _profile_device(cls.team_id) if cls.team_id else None
        if not cls.team_id or not cls.device_id:
            raise unittest.SkipTest("needs an Xcode Team with a local GoFly provisioning profile")
        cls.bundle_id = bundle_id_for_team(cls.team_id)

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="gofly-ipa-e2e-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.root = root
        resources = root / "Resources"
        shutil.copytree(BRIDGE_ROOT.parent / "SigningStub", resources / "SigningStub")
        self.state = root / "Support" / "GoFly" / "state"
        self.state.parent.mkdir(parents=True, mode=0o700)
        os.chmod(self.state.parent, 0o700)
        self.config = SetupConfiguration(resources, resources / "python", DEVELOPER,
                                         resources / "SigningStub" / "GoFly.xcodeproj",
                                         self.bundle_id, "GoFly", self.state)
        self.phone = SimulatedPhone(self.device_id, self.bundle_id)
        self.bridge = bridge.Bridge(bridge.Config(resources, Path("/unused"), DEVELOPER,
                                                  resources / "SigningStub" / "GoFly.xcodeproj",
                                                  state_root=self.state))
        self.downloads = root / "Downloads"
        self.downloads.mkdir()
        self.ipa = make_signed_ipa(_source_ipa(), self.downloads)

    def producer(self) -> SetupProducer:
        return SetupProducer(self.config, device=self.phone, process=IpaResignProcessAdapter(self.config),
                             artifact_validator=FormalArtifactValidator(team_is_free=xcode_team_is_free))

    def bridge_call(self, **fields: object) -> dict:
        return self.bridge.handle({"requestID": str(uuid.uuid4()), **fields})

    def apply(self, mode: str):
        request = {"requestID": str(uuid.uuid4()), "action": "apply", "setupID": str(uuid.uuid4()),
                   "deviceID": self.device_id.lower(), "mode": mode, "transport": "usb",
                   "options": {"teamID": self.team_id, "allowProvisioningUpdates": False}}
        producer = self.producer()

        def simulated_handoff(journal, *_args, **_kwargs):
            # Pairing delivery, device support and the activation receipt need a
            # real phone; record them as the simulated phone would confirm.
            journal = producer.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
            return producer.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})

        with mock.patch.object(SetupProducer, "_handoff", side_effect=simulated_handoff):
            return producer.handle(decode_request(json.dumps(request).encode()))

    def assert_installed_app_is_resigned(self) -> None:
        app = self.phone.installed_apps[-1]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], self.bundle_id)
        self.assertIs(info["GoFlyRequiresMacSetup"], True)
        self.assertEqual(info["BGTaskSchedulerPermittedIdentifiers"], [self.bundle_id + ".movement"])
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)

    def test_full_flow_install_renew_replace_and_reject(self) -> None:
        # 1. No saved IPA yet: the install stops before touching the phone.
        with self.assertRaises(SetupBridgeError) as missing:
            self.apply("install")
        self.assertEqual(missing.exception.code, "ipa-missing")
        self.assertEqual(self.phone.installed_apps, [])
        self.assertIsNone(self.bridge._project_identity()[0])

        # 2. D15b: choose the IPA and its signature from the same folder.
        saved = self.bridge_call(action="ipaImport", ipaPath=str(self.ipa), sigPath=str(self.ipa) + ".sig")
        self.assertEqual(saved["status"], "ok", saved)
        version, build = saved["payload"]["version"], saved["payload"]["build"]
        self.assertEqual(self.bridge._project_identity(), (version, build))

        # 3. First install over USB re-signs the saved IPA and completes.
        result = self.apply("install")
        self.assertEqual((result.stage, result.outcome), ("complete", "confirmed"), result.as_dict())
        self.assert_installed_app_is_resigned()

        # 4. The original download can disappear: renewal uses the saved copy.
        shutil.rmtree(self.downloads)
        result = self.apply("renew")
        self.assertEqual((result.stage, result.outcome), ("complete", "confirmed"), result.as_dict())
        self.assertEqual(len(self.phone.installed_apps), 2)
        self.assert_installed_app_is_resigned()

        # 5. A tampered file and a downgrade are refused; the saved IPA stays.
        self.downloads.mkdir()
        newer = make_signed_ipa(_source_ipa(), self.downloads, version="99.0.0", build="1")
        tampered = self.downloads / "tampered.ipa"
        shutil.copyfile(newer, tampered)
        with tampered.open("ab") as handle:
            handle.write(b"x")
        refused = self.bridge_call(action="ipaImport", ipaPath=str(tampered), sigPath=str(newer) + ".sig")
        self.assertEqual(refused.get("code"), "ipa-signature-invalid")
        older = make_signed_ipa(_source_ipa(), self.downloads, version="0.0.1", build="1")
        refused = self.bridge_call(action="ipaImport", ipaPath=str(older), sigPath=str(older) + ".sig",
                                   minimumVersion=version, minimumBuild=build)
        self.assertEqual(refused.get("code"), "ipa-downgrade")
        missing_sig = self.bridge_call(action="ipaImport", ipaPath=str(newer),
                                       sigPath=str(self.downloads / "absent.ipa.sig"))
        self.assertEqual(missing_sig.get("code"), "ipa-signature-missing")
        self.assertEqual(self.bridge._project_identity(), (version, build))

        # 6. D17 discovers a newer signed release, then downloads and installs it.
        url = "https://github.com/nevenhsu/GoFly-GPS/releases/download/v99.0.0/" + newer.name
        release = {"assets": [
            {"name": newer.name, "browser_download_url": url},
            {"name": newer.name + ".sig", "browser_download_url": url + ".sig"},
        ]}
        fixture = {url: newer, url + ".sig": Path(str(newer) + ".sig")}
        downloads = []

        def download(candidate, destination, **_kwargs):
            downloads.append(candidate)
            shutil.copyfile(fixture[candidate], destination)

        store_module = bridge._ipa_store_module()
        with (
            mock.patch.object(store_module, "_api_json", return_value=[release]),
            mock.patch.object(store_module, "download", side_effect=download),
        ):
            latest = self.bridge_call(action="ipaRelease")
            self.assertEqual(latest["status"], "ok", latest)
            self.assertEqual((latest["payload"]["version"], latest["payload"]["build"]), ("99.0.0", "1"))
            self.assertEqual(downloads, [url + ".sig"])
            replaced = self.bridge_call(action="ipaImport", ipaURL=latest["payload"]["ipaURL"],
                                        sigURL=latest["payload"]["sigURL"],
                                        minimumVersion=version, minimumBuild=build)
            self.assertEqual(downloads, [url + ".sig", url + ".sig", url])
        self.assertEqual(replaced["status"], "ok", replaced)
        self.assertEqual(self.bridge._project_identity(), ("99.0.0", "1"))
        result = self.apply("renew")
        self.assertEqual((result.stage, result.outcome), ("complete", "confirmed"), result.as_dict())
        self.assertEqual(self.phone.installed_build, "1")
        info = plistlib.loads((self.phone.installed_apps[-1] / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "99.0.0")

    def test_saved_ipa_tampered_on_disk_is_not_installed(self) -> None:
        saved = self.bridge_call(action="ipaImport", ipaPath=str(self.ipa), sigPath=str(self.ipa) + ".sig")
        self.assertEqual(saved["status"], "ok", saved)
        with (self.state / "ipa" / "current" / "GoFly.ipa").open("ab") as handle:
            handle.write(b"x")
        self.assertIsNone(self.bridge._project_identity()[0])
        with self.assertRaises(SetupBridgeError) as missing:
            self.apply("install")
        self.assertEqual(missing.exception.code, "ipa-missing")
        self.assertEqual(self.phone.installed_apps, [])

    def test_read_during_replacement_preserves_the_import(self) -> None:
        store = ipa_store.IpaStore(self.state)
        signature = Path(str(self.ipa) + ".sig").read_bytes()
        store.import_files(self.ipa, signature, source="file", source_name="original")
        verifying = threading.Event()
        finish_verifying = threading.Event()
        reading = threading.Event()
        inspect = ipa_store.inspect_ipa

        def inspect_staged(*args):
            verifying.set()
            if not finish_verifying.wait(5):
                raise TimeoutError("replacement test did not release verification")
            return inspect(*args)

        def read_current():
            reading.set()
            return ipa_store.IpaStore(self.state).current()

        with mock.patch.object(ipa_store, "inspect_ipa", side_effect=inspect_staged), ThreadPoolExecutor(2) as pool:
            pending_import = pool.submit(store.import_files, self.ipa, signature, source="file", source_name="replacement")
            try:
                self.assertTrue(verifying.wait(5))
                pending_read = pool.submit(read_current)
                self.assertTrue(reading.wait(5))
                # The reader may wait or read the old copy. It must never
                # recover the active import's staging directory as stale.
                try:
                    pending_read.result(timeout=0.5)
                except TimeoutError:
                    pass
            finally:
                finish_verifying.set()
            self.assertEqual(pending_import.result(timeout=5)["sourceName"], "replacement")
            self.assertIsNotNone(pending_read.result(timeout=5))
        self.assertEqual(store.current()["sourceName"], "replacement")

    def test_space_insufficient_is_distinguished_between_import_and_resign(self) -> None:
        import errno as _errno

        # 1. IPA import hitting ENOSPC reports ipa-import-space-insufficient.
        store_module = bridge._ipa_store_module()
        with mock.patch.object(store_module.shutil, "copyfile", side_effect=OSError(_errno.ENOSPC, "No space left on device")):
            failed_import = self.bridge_call(action="ipaImport", ipaPath=str(self.ipa), sigPath=str(self.ipa) + ".sig")
        self.assertEqual(failed_import.get("status"), "error")
        self.assertEqual(failed_import.get("code"), "ipa-import-space-insufficient")

        # 2. After a valid import, IPA re-sign hitting ENOSPC reports ipa-resign-space-insufficient.
        saved = self.bridge_call(action="ipaImport", ipaPath=str(self.ipa), sigPath=str(self.ipa) + ".sig")
        self.assertEqual(saved["status"], "ok", saved)
        with mock.patch.object(ipa_store.IpaStore, "extract_current",
                               side_effect=SetupBridgeError("ipa-resign-space-insufficient")):
            with self.assertRaises(SetupBridgeError) as failed_resign:
                self.apply("install")
        self.assertEqual(failed_resign.exception.code, "ipa-resign-space-insufficient")


if __name__ == "__main__":
    unittest.main()
