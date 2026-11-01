from __future__ import annotations

import contextlib
import asyncio
import io
import json
import os
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
import datetime as dt
from unittest import mock
from unittest.mock import AsyncMock
from types import SimpleNamespace
from pathlib import Path
import importlib.util

import sys

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(PACKAGE_ROOT))

from bridge import Config as BridgeConfig, run_stdio as bridge_run_stdio, _setup_error_payload as _error_payload  # noqa: E402
from setup_protocol import (  # noqa: E402
    SetupBridgeError,
    bundle_id_for_team,
    bundle_id_matches_team,
    decode_request,
    encode_response,
)
from setup_journal import JournalStore  # noqa: E402
from setup_adapters import (  # noqa: E402
    ArtifactIdentity,
    ActivationReceiptObservation,
    DeviceObservation,
    InstalledAppObservation,
    PairingObservation,
    PinnedPymobiledeviceAdapter,
    PinnedXcodeProcessAdapter,
    ReadbackObservation,
    SupportObservation,
    FormalArtifactValidator,
    snapshot_artifact,
    _run,
    close_async_runtime,
)
from setup_config import SetupConfiguration  # noqa: E402
from setup_producer import SetupProducer  # noqa: E402
from setup_producer import support_method  # noqa: E402
from setup_delivery import deliver_v1_once  # noqa: E402
from setup_support import validate_generation  # noqa: E402


DEVICE = "0123456789abcdef0123456789abcdef01234567"
TEAM_A_BUNDLE_ID = bundle_id_for_team("ABCDEFGHIJ")
SETUP_ID = str(uuid.uuid4())
REQUEST_ID = str(uuid.uuid4())


def request(action: str = "status", **extra: object) -> dict[str, object]:
    value: dict[str, object] = {
        "requestID": REQUEST_ID,
        "action": action,
        "setupID": SETUP_ID,
        "deviceID": DEVICE,
        "mode": "install",
    }
    value.update(extra)
    return value


class ProtocolB1Tests(unittest.TestCase):
    def test_bundle_id_is_scoped_to_each_team_without_legacy_fallback(self) -> None:
        self.assertTrue(bundle_id_matches_team(TEAM_A_BUNDLE_ID, "ABCDEFGHIJ"))
        self.assertNotEqual(TEAM_A_BUNDLE_ID, bundle_id_for_team("ABCDE12345"))
        self.assertFalse(bundle_id_matches_team("com.neven.gofly", "ABCDEFGHIJ"))
        self.assertFalse(bundle_id_matches_team("com.neven.gofly.abcdefghik", "ABCDEFGHIJ"))
        self.assertFalse(bundle_id_matches_team("com.neven.gofly.other", "ABCDEFGHIJ"))

    def test_free_team_signing_lasts_seven_days_from_signing(self) -> None:
        profile_expiry = dt.datetime(2027, 10, 26, 15, 38, tzinfo=dt.timezone.utc)
        created = dt.datetime(2026, 10, 26, 15, 38, tzinfo=dt.timezone.utc)
        profile = {"CreationDate": created}
        shown = b"Authority=Apple Development: X\nSigned Time=Nov 1, 2026 at 10:24:18\xe2\x80\xafPM\n"
        signed = dt.datetime(2026, 11, 1, 22, 24, 18).astimezone(dt.timezone.utc)

        free = FormalArtifactValidator(team_is_free=lambda _team: True)
        self.assertEqual(free.signing_expiry(profile_expiry, profile, shown, "ABCDEFGHIJ"),
                         signed + dt.timedelta(days=7))
        self.assertEqual(free.signing_expiry(profile_expiry, profile, b"", "ABCDEFGHIJ"),
                         created + dt.timedelta(days=7), "Without a signing time the profile's creation anchors it.")
        for lookup in (lambda _team: False, lambda _team: None, None):
            validator = FormalArtifactValidator(team_is_free=lookup)
            self.assertEqual(validator.signing_expiry(profile_expiry, profile, shown, "ABCDEFGHIJ"), profile_expiry)

    def test_xcode_build_uses_the_selected_team_bundle_identifier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            project_root = workspace / "app" / "GoFly"
            project = project_root / "GoFly.xcodeproj"
            project.mkdir(parents=True)
            (project / "project.pbxproj").write_text("fixture")
            (workspace / "work" / "gofly-ios" / "native").mkdir(parents=True)
            developer = root / "Developer"
            developer.mkdir()
            seen = []

            def fake_xcodebuild(arguments, **_kwargs):
                seen.append(arguments)
                destination = next(value.split("=", 1)[1] for value in arguments
                                   if value.startswith("CONFIGURATION_BUILD_DIR="))
                (Path(destination) / "GoFly.app").mkdir()
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            for team_id in ("ABCDE12345", "ABCDEFGHIJ"):
                config = SetupConfiguration(
                    workspace, workspace / "work" / "mac-setup-env" / "bin" / "python",
                    developer, project, bundle_id_for_team(team_id), "GoFly", root / "state",
                    development_mode=True,
                )
                with mock.patch("setup_adapters.subprocess.run", side_effect=fake_xcodebuild):
                    result = PinnedXcodeProcessAdapter(config).build(str(uuid.uuid4()), team_id)
                self.assertTrue(result.is_dir())

            self.assertEqual(len(seen), 2)
            for arguments, team_id in zip(seen, ("ABCDE12345", "ABCDEFGHIJ")):
                expected = bundle_id_for_team(team_id)
                self.assertIn("DEVELOPMENT_TEAM=" + team_id, arguments)
                self.assertIn("PRODUCT_BUNDLE_IDENTIFIER=" + expected, arguments)
                self.assertIn("GOFLY_BUNDLE_ID=" + expected, arguments)
                self.assertNotIn("-allowProvisioningDeviceRegistration", arguments)

            config = SetupConfiguration(
                workspace, workspace / "work" / "mac-setup-env" / "bin" / "python",
                developer, project, bundle_id_for_team("ABCDE12345"), "GoFly", root / "state",
                development_mode=True,
            )
            with mock.patch("setup_adapters.subprocess.run", side_effect=fake_xcodebuild):
                PinnedXcodeProcessAdapter(config).build(
                    str(uuid.uuid4()), "ABCDE12345", True, register_device_id="00008160-00180cc03e00000a")
            arguments = seen[-1]
            self.assertIn("-allowProvisioningUpdates", arguments)
            self.assertIn("-allowProvisioningDeviceRegistration", arguments)
            destination = arguments[arguments.index("-destination") + 1]
            self.assertEqual(destination, "platform=iOS,id=00008160-00180CC03E00000A")

    def test_json_constants_nan_and_infinity_are_safe_invalid_request(self) -> None:
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "deviceID": float("nan")}).encode())
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "deviceID": float("inf")}).encode())

    def test_request_rejects_unknown_and_duplicate_keys(self) -> None:
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps(request(extraKey=True)).encode())
        duplicate = (
            '{"protocol":2,"requestID":"%s","operation":"setup",'
            '"action":"status","setupID":"%s","deviceID":"%s",'
            '"deviceID":"%s"}'
            % (REQUEST_ID, SETUP_ID, DEVICE, DEVICE)
        )
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(duplicate.encode())

    def test_apply_requires_exact_options_and_project_shape(self) -> None:
        valid = request(
            "apply",
            options={
                "teamID": "ABCDEFGHIJ",
                "allowProvisioningUpdates": False,
            },
        )
        decoded = decode_request(json.dumps(valid).encode())
        self.assertEqual(decoded.options.team_id, "ABCDEFGHIJ")
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(
                json.dumps(
                    request(
                        "apply",
                        options={
                            "artifactPath": "/tmp/GoFly.app",
                            "teamID": "ABCDEFGHIJ",
                            "allowProvisioningUpdates": False,
                        },
                    )
                ).encode()
            )

    def test_response_requires_all_proof_fields_and_is_bounded(self) -> None:
        payload = {
            "stage": "preflight",
            "outcome": "ready",
            "proof": {
                "installationConfirmed": False,
                "pairingImported": False,
                "supportObserved": False,
            },
        }
        encoded = encode_response(
            request("preflight"),
            status="ok",
            payload=payload,
        )
        self.assertLessEqual(len(encoded), 256 * 1024)
        self.assertEqual(json.loads(encoded)["payload"]["proof"], payload["proof"])

class JournalB1Tests(unittest.TestCase):
    def test_legacy_transaction_can_be_read_and_archived_without_reusing_its_bundle_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory) / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "teamID": "ABCDEFGHIJ",
                "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly",
            })
            self.assertEqual(store.read()["intent"]["targetBundleID"], "com.neven.gofly")
            with store.lock():
                store.abandon_unfinished_locked(SETUP_ID, DEVICE)
            self.assertTrue((store.transaction_root(SETUP_ID) / "journal.abandoned.json").is_file())

    def test_delivery_unknown_status_is_query_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            config = SetupConfiguration(root, root / "python", root / "Developer", project,
                                        TEAM_A_BUNDLE_ID, "GoFly", state)
            store = JournalStore(state)
            journal = store.create(SETUP_ID, DEVICE, {
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": TEAM_A_BUNDLE_ID, "targetName": "GoFly",
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            journal["delivery"] = {"state": "unknown"}
            store.update(journal)
            producer = SetupProducer(config, store=store, device=ReadOnlyStatusDevice())
            payload = producer.status(decode_request(json.dumps(request("status")).encode()))
            self.assertEqual(payload.stage, "artifact")
            self.assertEqual(payload.outcome, "inProgress")
            self.assertEqual(producer.device.verify_calls, 0)
            self.assertEqual(producer.device.pair_calls, 0)
            error_payload = _error_payload(decode_request(json.dumps(request("status")).encode()), config)
            self.assertNotIn("canResume", error_payload)

    def test_unfinished_journal_is_archived_before_a_fresh_setup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            store = JournalStore(state)
            journal = store.create(SETUP_ID, DEVICE, {
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": TEAM_A_BUNDLE_ID, "targetName": "GoFly",
            })
            journal["stages"]["install"] = {"state": "unknown", "detail": "device-disconnected"}
            store.update(journal)

            class ExistingDevice:
                def observe(self, device_id: str) -> DeviceObservation:
                    return DeviceObservation(device_id, "27.0", "USB", True, True)

                def installed(self, _device_id: str) -> InstalledAppObservation:
                    return InstalledAppObservation(False)

            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                TEAM_A_BUNDLE_ID, "GoFly", state,
            )
            producer = SetupProducer(config, store=store, device=ExistingDevice())
            replacement = request(
                "apply",
                setupID=str(uuid.uuid4()),
                mode="install",
                options={
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                },
            )
            try:
                producer.handle(decode_request(json.dumps(replacement).encode()))
            except SetupBridgeError as error:
                self.assertNotEqual(str(error), "transaction-conflict")
            self.assertNotEqual(store.read()["setupID"], SETUP_ID)
            self.assertEqual(store.read()["stages"]["artifact"]["state"], "unknown")
            self.assertTrue((store.transaction_root(SETUP_ID) / "journal.abandoned.json").is_file())

    def test_reopen_maps_inflight_stage_and_delivery_to_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory))
            journal = store.create(SETUP_ID, DEVICE, {
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": TEAM_A_BUNDLE_ID, "targetName": "GoFly",
            })
            journal["stages"]["install"] = {"state": "inflight"}
            journal["delivery"] = {"state": "inflight"}
            store.update(journal)
            snapshot = store.reopen_snapshot()
            self.assertEqual(snapshot["stages"]["install"]["state"], "unknown")
            self.assertEqual(snapshot["delivery"]["state"], "unknown")
            self.assertEqual(store.read()["stages"]["install"]["state"], "inflight")

    def test_install_unknown_never_resubmits_or_adopts_matching_observation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            (root / "Developer").mkdir()
            config = SetupConfiguration(root, root / "python", root / "Developer", project,
                                        TEAM_A_BUNDLE_ID, "GoFly", root / "state")
            # The production snapshot boundary requires a real source tree;
            # the validator remains the controlled seam for this test.
            (root / "GoFly.app").mkdir()
            device = UnknownInstallDevice()
            producer = SetupProducer(
                config,
                device=device,
                process=FakeProcess(root / "state"),
                artifact_validator=FakeArtifactValidator(),
            )
            apply_request = request(
                "apply",
                options={
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                },
            )
            # The validator is controlled, so no filesystem artifact or Apple
            # tool is reached by this test.
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                with self.assertRaisesRegex(SetupBridgeError, "operation-failed"):
                    producer.handle(decode_request(json.dumps(apply_request).encode()))
            journal = JournalStore(root / "state").read()
            self.assertEqual(journal["stages"]["pairing"]["state"], "confirmed")
            self.assertEqual(journal["stages"]["install"]["state"], "unknown")

            with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
                decode_request(json.dumps(request("resume")).encode())
            self.assertEqual(device.install_calls, 1)
            self.assertEqual(device.launch_calls, 0)
            self.assertEqual(device.delivery_calls, 0)

class FakeArtifactValidator:
    def inspect(
        self, _path: str, *, device_id: str, team_id: str, target_bundle_id: str | None = None
    ) -> ArtifactIdentity:
        return ArtifactIdentity(
            str(_path),
            target_bundle_id or TEAM_A_BUNDLE_ID,
            "GoFly",
            team_id,
            "a" * 64,
            "b" * 64,
            "c" * 64,
            "2030-01-01T00:00:00Z",
            {},
            "19",
        )


class FakeProcess:
    def __init__(self, state_root: Path) -> None:
        self.state_root = state_root

    def build(self, setup_id: str, *_args, **_kwargs) -> Path:
        path = self.state_root / "transactions" / setup_id / "build" / "GoFly.app"
        path.mkdir(parents=True, exist_ok=True)
        return path


class UnknownInstallDevice:
    def __init__(self) -> None:
        self.install_calls = 0
        self.launch_calls = 0
        self.delivery_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def installed(self, device_id: str) -> InstalledAppObservation:
        # The app appears only after the controlled install boundary, which
        # then raises before a durable success result is returned.
        return InstalledAppObservation(self.install_calls > 0, TEAM_A_BUNDLE_ID, "a" * 64, "b" * 64, "c" * 64)

    def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
        candidate.parent.mkdir(parents=True, exist_ok=True)
        candidate.write_bytes(b"pairing")
        candidate.chmod(0o600)

    def pair(self, device_id: str, candidate: Path) -> PairingObservation:
        return PairingObservation("verified", device_id, "d" * 64)

    def verify_pairing(self, device_id: str, candidate: Path) -> PairingObservation:
        return PairingObservation("verified", device_id, "d" * 64)

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.install_calls += 1
        raise RuntimeError("controlled process death")

    def query_support(self, device_id: str, method: str) -> SupportObservation:
        return SupportObservation(True, method, "27.0", "generation", "com.apple.MobileAsset.DDI", "1")

    def install_support(self, device_id: str, method: str, restore_dir: Path) -> SupportObservation:
        raise AssertionError("support must not run after unknown install")

    def deliver_pairing(self, device_id: str, setup_id: str) -> None:
        self.delivery_calls += 1

    def launch(self, device_id: str) -> None:
        self.launch_calls += 1

    def stop(self, device_id: str) -> None:
        raise AssertionError("stop must not run after unknown install")

    def readback(self, device_id: str, setup_id: str, nonce: str) -> None:
        raise AssertionError("readback must not run after unknown install")


class ReadOnlyStatusDevice:
    def __init__(self) -> None:
        self.verify_calls = 0
        self.pair_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def verify_pairing(self, device_id: str, candidate: Path) -> PairingObservation:
        self.verify_calls += 1
        return PairingObservation("verified", device_id, "d" * 64)

    def pair(self, device_id: str, candidate: Path) -> PairingObservation:
        self.pair_calls += 1
        raise AssertionError("status must not run pair setup")


class ChangingBoundaryDevice:
    def __init__(self) -> None:
        self.boundary_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        self.boundary_calls += 1
        return DeviceObservation(device_id, "26.4.0", "USB", True, True)



class RenewDevice:
    def __init__(self, present: bool = True, fail_install: bool = False) -> None:
        self.present = present
        self.fail_install = fail_install
        self.install_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def installed(self, device_id: str) -> InstalledAppObservation:
        return InstalledAppObservation(self.present, TEAM_A_BUNDLE_ID)

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.install_calls += 1
        if self.fail_install:
            raise RuntimeError("controlled process death")
        return InstalledAppObservation(True, TEAM_A_BUNDLE_ID, build=artifact.build)

    def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
        candidate.write_bytes(b"pairing")
        candidate.chmod(0o600)

    def pair(self, *_args: object) -> PairingObservation:
        return PairingObservation("verified", DEVICE, "d" * 64)

    def verify_pairing(self, *_args: object) -> PairingObservation:
        return PairingObservation("verified", DEVICE, "d" * 64)

    def deliver_pairing(self, *_args: object) -> None:
        raise AssertionError("renew must not deliver pairing")

    def launch(self, *_args: object) -> None:
        raise AssertionError("renew must not launch")

    def stop(self, *_args: object) -> None:
        raise AssertionError("renew must not stop")

    def readback(self, *_args: object) -> None:
        raise AssertionError("renew must not read back")

    def query_support(self, *_args: object) -> SupportObservation:
        raise AssertionError("renew must not query support")

    def install_support(self, *_args: object) -> SupportObservation:
        raise AssertionError("renew must not install support")


class RenewB1Tests(unittest.TestCase):
    def producer(self, directory: str, device: RenewDevice) -> SetupProducer:
        root = Path(directory)
        (root / "GoFly.app").mkdir(exist_ok=True)
        (root / "GoFly.xcodeproj").mkdir(exist_ok=True)
        (root / "Developer").mkdir(exist_ok=True)
        (root / "python").touch()
        config = SetupConfiguration(
            root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
            TEAM_A_BUNDLE_ID, "GoFly", root / "state",
        )
        return SetupProducer(config, device=device, process=FakeProcess(root / "state"),
                             artifact_validator=FakeArtifactValidator())

    def options(self, root: Path) -> dict[str, object]:
        return {
            "teamID": "ABCDEFGHIJ",
            "allowProvisioningUpdates": False,
        }

    def test_renew_preflight_rejects_a_missing_app(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            producer = self.producer(directory, RenewDevice(present=False))
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None):
                with self.assertRaisesRegex(SetupBridgeError, "app-not-installed"):
                    producer.handle(decode_request(json.dumps(request(
                        "preflight", mode="renew", options=self.options(root)
                    )).encode()))

    def test_renew_apply_requires_pairing_and_full_handoff(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = RenewDevice()
            producer = self.producer(directory, device)
            def confirmed_handoff(journal, *_args):
                journal = producer.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
                return producer.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})

            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
                 mock.patch.object(producer, "_handoff", side_effect=confirmed_handoff) as handoff:
                result = producer.handle(decode_request(json.dumps(request(
                    "apply", mode="renew", options=self.options(root)
                )).encode()))
            handoff.assert_called_once()
            self.assertEqual(result.stage, "complete", result.as_dict())
            self.assertEqual(result.outcome, "confirmed")
            self.assertTrue(result.installation_confirmed)
            self.assertTrue(result.pairing_imported)
            self.assertTrue(result.support_observed)
            self.assertEqual(result.expires_at, "2030-01-01T00:00:00Z")
            journal = JournalStore(root / "state").read()
            self.assertEqual(set(journal["stages"]), {"artifact", "pairing", "install", "support", "handoff", "complete"})
            self.assertIs(journal["intent"]["fullSetup"], True)
            self.assertEqual(journal["stages"]["pairing"]["state"], "confirmed")
            self.assertEqual(device.install_calls, 1)

    def test_renew_unknown_install_status_is_read_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = RenewDevice(fail_install=True)
            producer = self.producer(directory, device)
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                with self.assertRaises(SetupBridgeError):
                    producer.handle(decode_request(json.dumps(request(
                        "apply", mode="renew", options={
                            "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                        }
                    )).encode()))
                self.assertEqual(device.install_calls, 1)
                result = producer.status(decode_request(json.dumps(request("status", mode="renew")).encode()))
            self.assertEqual(result.outcome, "unknown")
            self.assertEqual(result.stage, "install")
            self.assertEqual(device.install_calls, 1)

    def test_install_mode_still_rejects_an_existing_app(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            producer = self.producer(directory, RenewDevice(present=True))
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None):
                with self.assertRaisesRegex(SetupBridgeError, "app-already-installed"):
                    producer.handle(decode_request(json.dumps(request(
                        "preflight", mode="install", options=self.options(root)
                    )).encode()))



class FullRenewRegressionTests(unittest.TestCase):
    producer = RenewB1Tests.producer
    options = RenewB1Tests.options
    def test_resume_action_is_rejected(self):
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(request("resume", mode="renew"))

    def test_renew_pairing_unknown_never_installs_or_generates_again(self):
        with tempfile.TemporaryDirectory() as directory:
            device = RenewDevice()
            producer = self.producer(directory, device)
            with mock.patch.object(device, "pair", side_effect=SetupBridgeError("pairing-unknown")) as pair, \
                 mock.patch.object(device, "verify_pairing", return_value=PairingObservation("unknown")), \
                 mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                with self.assertRaisesRegex(SetupBridgeError, "pairing-unknown"):
                    producer.handle(decode_request(request("apply", mode="renew", options=self.options(Path(directory)))))
            self.assertEqual(pair.call_count, 1)
            self.assertEqual(device.install_calls, 0)

    def test_renew_handoff_failure_cannot_report_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            producer = self.producer(directory, RenewDevice())
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
                 mock.patch.object(producer, "_handoff", side_effect=SetupBridgeError("handoff-unknown")):
                with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
                    producer.handle(decode_request(request("apply", mode="renew", options=self.options(Path(directory)))))
            result = producer.handle(decode_request(request("status", mode="renew")))
            self.assertFalse(result.pairing_imported)
            self.assertNotEqual(result.stage, "complete")


class RestartFromScratchStageTests(unittest.TestCase):
    def producer(self, root: Path, device: RenewDevice) -> SetupProducer:
        (root / "GoFly.app").mkdir(exist_ok=True)
        (root / "GoFly.xcodeproj").mkdir(exist_ok=True)
        (root / "Developer").mkdir(exist_ok=True)
        (root / "python").touch()
        config = SetupConfiguration(
            root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
            TEAM_A_BUNDLE_ID, "GoFly", root / "state",
        )
        return SetupProducer(config, device=device, process=FakeProcess(root / "state"),
                             artifact_validator=FakeArtifactValidator())

    def test_same_setup_id_conflicts_before_disconnected_device_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = RenewDevice()
            producer = self.producer(root, device)
            producer.store.create(SETUP_ID, DEVICE, {
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": TEAM_A_BUNDLE_ID, "targetName": "GoFly",
                "fullSetup": True,
            }, mode="renew")

            with mock.patch.object(
                device, "observe", side_effect=SetupBridgeError("device-disconnected")
            ) as observe:
                with self.assertRaisesRegex(SetupBridgeError, "transaction-conflict"):
                    producer.handle(decode_request(json.dumps(request(
                        "apply", mode="renew", options={
                            "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                        }
                    )).encode()))
            observe.assert_not_called()

    def test_each_interrupted_stage_archives_old_input_and_starts_a_fresh_pairing_transaction(self):
        class RestartDevice(RenewDevice):
            def __init__(self):
                super().__init__(present=True)
                self.pairing_candidates = []
                self.retired = []

            def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
                candidate.write_bytes(b"fresh-pairing-candidate")
                candidate.chmod(0o600)
                self.pairing_candidates.append(candidate)

            def pair(self, *_args: object) -> PairingObservation:
                return PairingObservation("verified", DEVICE, "e" * 64)

            def verify_pairing(self, *_args: object) -> PairingObservation:
                return PairingObservation("verified", DEVICE, "e" * 64)

            def retire_pending_pairing(self, device_id: str, transaction_id: str) -> None:
                self.retired.append((device_id, transaction_id))

        for interrupted_stage in ("artifact", "pairing", "install", "support", "handoff"):
            with self.subTest(stage=interrupted_stage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                device = RestartDevice()
                producer = self.producer(root, device)
                old_setup_id = SETUP_ID
                old_transaction_id = str(uuid.uuid4())
                store = producer.store
                old = store.create(old_setup_id, DEVICE, {
                    "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                    "targetBundleID": TEAM_A_BUNDLE_ID, "targetName": "GoFly",
                    "pairingTransactionID": old_transaction_id,
                    "fullSetup": True,
                }, mode="renew")
                stage_order = ("artifact", "pairing", "install", "support", "handoff", "complete")
                for stage in stage_order:
                    old["stages"][stage] = {"state": "confirmed" if stage_order.index(stage) < stage_order.index(interrupted_stage) else "pending"}
                old["stages"][interrupted_stage] = {"state": "unknown", "detail": "controlled interruption"}
                store.update(old)
                old_candidate = store.transaction_root(old_setup_id) / "pairing.candidate"
                old_candidate.write_bytes(b"old-transaction-pairing")
                old_candidate.chmod(0o600)
                new_setup_id = str(uuid.uuid4())
                new_request = request("apply", setupID=new_setup_id, mode="renew", options={
                    "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                })
                def fail_handoff(journal, *_args):
                    producer.store.checkpoint(journal, "handoff", "inflight")
                    raise SetupBridgeError("handoff-unknown")

                with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
                     mock.patch.object(producer, "_handoff", side_effect=fail_handoff):
                    with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
                        producer.handle(decode_request(json.dumps(new_request).encode()))

                current = store.read()
                self.assertEqual(current["setupID"], new_setup_id)
                self.assertEqual(current["mode"], "renew")
                self.assertEqual(current["stages"]["handoff"]["state"], "unknown", current["stages"])
                self.assertEqual(current["stages"]["pairing"]["state"], "confirmed")
                self.assertEqual(device.install_calls, 1)
                self.assertEqual(len(device.pairing_candidates), 1)
                self.assertEqual(device.pairing_candidates[0], store.transaction_root(new_setup_id) / "pairing.candidate")
                self.assertNotEqual(device.pairing_candidates[0], store.transaction_root(old_setup_id) / "pairing.candidate")
                archived_candidate = store.transaction_root(old_setup_id) / "pairing.candidate"
                self.assertEqual(archived_candidate.read_bytes(), b"old-transaction-pairing")
                expected_retired = [(DEVICE, old_transaction_id)] if interrupted_stage == "handoff" else []
                self.assertEqual(device.retired, expected_retired)


class AdapterBoundaryTests(unittest.TestCase):
    """The two single-point regressions kept from the deleted USB/process files."""

    serial = "00000000-000000000000ABCD"

    def tearDown(self) -> None:
        close_async_runtime()

    def test_normalized_identity_opens_exact_usb_serial_without_autopair(self) -> None:
        client = SimpleNamespace(get_value=AsyncMock(return_value={"UniqueDeviceID": self.serial}), close=AsyncMock())
        create = AsyncMock(return_value=client)
        adapter = PinnedPymobiledeviceAdapter()
        adapter._modules = (
            SimpleNamespace(list_devices=AsyncMock(return_value=[SimpleNamespace(serial=self.serial, connection_type="USB")])),
            SimpleNamespace(create_using_usbmux=create),
            SimpleNamespace(),
        )
        with tempfile.TemporaryDirectory() as directory:
            self.assertIs(adapter._open(self.serial.lower(), Path(directory)), client)
        self.assertEqual(create.call_args.kwargs["serial"], self.serial)
        self.assertIs(create.call_args.kwargs["autopair"], False)
        self.assertEqual(create.call_args.kwargs["connection_type"], "USB")

    def test_launch_uses_verified_rsd_and_never_kills_existing(self) -> None:
        device = "00000000-000000000000abcd"
        adapter = PinnedPymobiledeviceAdapter(target_bundle_id=TEAM_A_BUNDLE_ID)

        def serial(value: str) -> str:
            self.assertEqual(value, device)
            with self.assertRaises(RuntimeError):
                asyncio.get_running_loop()
            return device.upper()

        adapter.transport_serial = serial
        rsd = SimpleNamespace(udid=device, product_version="27.0.1")
        tunnel = SimpleNamespace(aopen=mock.AsyncMock(return_value=rsd), aclose=mock.AsyncMock())
        control = mock.MagicMock()
        control.__aenter__ = mock.AsyncMock(return_value=control)
        control.__aexit__ = mock.AsyncMock(return_value=False)
        control.process_identifier_for_bundle_identifier = mock.AsyncMock(return_value=0)
        control.launch = mock.AsyncMock(return_value=123)
        provider = mock.MagicMock()
        provider.__aenter__ = mock.AsyncMock(return_value=provider)
        provider.__aexit__ = mock.AsyncMock(return_value=False)
        modules = {
            "pymobiledevice3.remote.userspace_tunnel": SimpleNamespace(UserspaceRsdTunnel=mock.Mock(return_value=tunnel)),
            "pymobiledevice3.services.dvt.instruments.process_control": SimpleNamespace(ProcessControl=mock.Mock(return_value=control)),
            "pymobiledevice3.services.dvt.instruments.dvt_provider": SimpleNamespace(DvtProvider=mock.Mock(return_value=provider)),
        }
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            self.assertEqual(adapter.launch(device), 123)
        control.launch.assert_awaited_once_with(TEAM_A_BUNDLE_ID, kill_existing=False)
        tunnel.aclose.assert_awaited_once()

    @unittest.skipUnless(
        all(importlib.util.find_spec(name) is not None for name in ("pymobiledevice3", "cryptography")),
        "pymobiledevice3／cryptography 未安裝，跳過裝置依賴測試",
    )
    def test_pinned_device_dependencies_are_available(self) -> None:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from pymobiledevice3.services.cryptexd import load_cryptex1_assets
        self.assertTrue(callable(load_cryptex1_assets))
        self.assertTrue(callable(Ed25519PrivateKey.generate))


class InstallDevice(RenewDevice):
    def __init__(self) -> None:
        super().__init__(present=False)
        self.installed_present = False

    def installed(self, device_id: str) -> InstalledAppObservation:
        return InstalledAppObservation(self.installed_present, TEAM_A_BUNDLE_ID)

    def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
        candidate.write_bytes(b"pairing")

    def pair(self, _device_id: str, _candidate: Path) -> PairingObservation:
        return PairingObservation("verified", DEVICE, "a" * 64)

    def verify_pairing(self, _device_id: str, _candidate: Path) -> PairingObservation:
        return PairingObservation("verified", DEVICE, "a" * 64)

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.installed_present = True
        return InstalledAppObservation(True, TEAM_A_BUNDLE_ID, build=artifact.build)


class InstallApplyTests(unittest.TestCase):
    def test_install_apply_reaches_complete_with_the_full_stage_list(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "GoFly.app").mkdir()
            (root / "GoFly.xcodeproj").mkdir()
            (root / "Developer").mkdir()
            (root / "python").touch()
            config = SetupConfiguration(root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                                        TEAM_A_BUNDLE_ID, "GoFly", root / "state")
            producer = SetupProducer(config, device=InstallDevice(),
                                     process=FakeProcess(root / "state"),
                                     artifact_validator=FakeArtifactValidator())
            options = {"teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False}
            def fake_handoff(journal, *_args, **_kwargs):
                journal = producer.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
                return producer.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})

            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
                 mock.patch.object(SetupProducer, "_handoff", side_effect=fake_handoff):
                result = producer.handle(decode_request(json.dumps(request("apply", mode="install", options=options)).encode()))
            self.assertEqual(result.stage, "complete", result.as_dict())
            self.assertEqual(result.outcome, "confirmed")
            self.assertTrue(result.installation_confirmed and result.pairing_imported and result.support_observed)
            journal = JournalStore(root / "state").read()
            self.assertEqual(set(journal["stages"]), {"artifact", "pairing", "install", "support", "handoff", "complete"})

class StdioB1Tests(unittest.TestCase):
    def test_process_group_owns_controlled_child_tree_for_cancel(self) -> None:
        bridge = Path(__file__).resolve().parents[2] / "bridge.py"
        script = (
            "import os, subprocess, sys, time; "
            f"sys.path.insert(0, {str(bridge.parent)!r}); import bridge; bridge.establish_process_group(); "
            "child=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
            "print(f'{os.getpid()} {child.pid}', flush=True); time.sleep(30)"
        )
        process = subprocess.Popen(
            [sys.executable, "-I", "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        grandchild_pid: int | None = None
        try:
            line = process.stdout.readline() if process.stdout is not None else ""
            parent_pid, grandchild_text = line.strip().split()
            self.assertEqual(int(parent_pid), process.pid)
            grandchild_pid = int(grandchild_text)
            os.kill(-process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            time.sleep(0.1)
            with self.assertRaises(ProcessLookupError):
                os.kill(grandchild_pid, 0)
        finally:
            if process.poll() is None:
                os.kill(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            if grandchild_pid is not None:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(grandchild_pid, signal.SIGKILL)
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()

    def test_invalid_request_has_bounded_protocol2_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = BridgeConfig(root, root / "python", root / "Developer", root / "GoFly.xcodeproj")
            response = bridge_run_stdio(config, stdin=io.BytesIO(b"{}"))
            self.assertEqual(response["status"], "error")
            self.assertEqual(response["code"], "invalid-request")

    def test_bundle_setup_paths_derive_without_configuration_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration.from_bundle(root, root / "Developer")
            self.assertEqual(config.project_path, root / "iOSProject/GoFly.xcodeproj")
            self.assertEqual(config.python_path, root / "Python/python/install/bin/python3.14")
            self.assertEqual(config.state_root, Path.home() / "Library/Application Support/GoFly/state")

    def test_error_payload_query_does_not_create_a_state_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            config = SimpleNamespace(state_root=state)
            response = _error_payload(SimpleNamespace(action="apply", setup_id=None, device_id=None), config)
            self.assertEqual(response["outcome"], "unknown")
            self.assertEqual(response["stage"], "preflight")
            self.assertFalse(state.exists())

if __name__ == "__main__":
    unittest.main()
