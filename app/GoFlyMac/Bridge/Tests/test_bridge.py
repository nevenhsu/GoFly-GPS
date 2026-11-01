from __future__ import annotations

import io
import asyncio
import json
import plistlib
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import bridge  # noqa: E402


UDID = "0123456789abcdef0123456789abcdef01234567"
RID = str(uuid.uuid4())
TEAM_ID = "ABCDEFGHIJ"
TARGET_BUNDLE_ID = "com.neven.gofly.abcdefghij"


class FakeClient:
    def __init__(self, values, developer=True):
        self.values = values
        self.developer = developer
        self.closed = False
        self.loop_ids = set()

    async def get_value(self, domain=None, key=None):
        self.loop_ids.add(id(asyncio.get_running_loop()))
        if domain == "com.apple.security.mac.amfi" and key == "DeveloperModeStatus":
            return self.developer
        return self.values

    async def close(self):
        self.loop_ids.add(id(asyncio.get_running_loop()))
        self.closed = True


class FakeDeviceModule:
    def __init__(self, rows, client=None):
        self.rows = rows
        self.client = client
        self.calls = []

    def check_compatibility(self):
        return None

    async def list_usb_devices(self):
        return self.rows

    async def open_lockdown(self, serial, connection, cache, *, autopair):
        self.calls.append((serial, connection, autopair))
        return self.client


class BridgeTests(unittest.TestCase):
    def config(self):
        root = Path(tempfile.mkdtemp())
        project = root / "StikDebug.xcodeproj"
        project.mkdir()
        return bridge.Config(root, root / "python", root / "Developer", project)

    def device(self, rows, client=None):
        return FakeDeviceModule(rows, client)

    def test_request_uuid_and_bounds(self):
        self.assertEqual(bridge._validate_request({"requestID": RID, "action": "devices"}), "devices")
        with self.assertRaisesRegex(bridge.BridgeError, "invalid-request"):
            bridge._validate_request({"requestID": "bad", "action": "devices"})
        self.assertEqual(len(bridge.read_request(io.BytesIO(b"a" * bridge.MAX_REQUEST_BYTES))),
                         bridge.MAX_REQUEST_BYTES)
        with self.assertRaises(bridge.BridgeError):
            bridge.read_request(io.BytesIO(b"a" * (bridge.MAX_REQUEST_BYTES + 1)))

    def test_internal_error_codes_are_normalized(self):
        self.assertEqual(bridge._map_error("SECRET-PAIRING-DATA"), "operation-failed")
        self.assertEqual(bridge.BridgeError("unexpected-internal").code, "operation-failed")

    def test_device_connections_remain_explicit_and_skip_unknown_transport(self):
        rows = [
            SimpleNamespace(serial=UDID, connection_type="Network"),
            SimpleNamespace(serial=UDID.upper(), connection_type="USB", name="Phone"),
            SimpleNamespace(serial="not-an-udid", connection_type="USB"),
        ]
        instance = bridge.Bridge(self.config(), self.device(rows))
        result = instance.devices()
        self.assertEqual({item["transport"] for item in result["devices"]}, {"usb", "wifi"})
        self.assertEqual(len(result["devices"]), 2)
        self.assertEqual(instance._find_device(rows, UDID)[2], "USB")
        self.assertEqual(instance._find_device(rows, UDID, "wifi")[2], "Network")
        with self.assertRaisesRegex(bridge.BridgeError, "device-disconnected"):
            instance._find_device(rows[1:], UDID, "wifi")
        self.assertEqual(bridge._validate_request({"requestID": RID, "action": "inspect",
                                                 "deviceID": UDID, "transport": "wifi",
                                                 "teamID": TEAM_ID}), "inspect")
        with self.assertRaisesRegex(bridge.BridgeError, "invalid-request"):
            bridge._validate_request({"requestID": RID, "action": "inspect",
                                      "deviceID": UDID, "transport": ["wifi"]})

    def test_device_list_reads_the_phone_name_over_usb_without_pairing(self):
        client = FakeClient({"UniqueDeviceID": UDID, "DeviceName": "Lilian’s iPhone"})
        client.get_value = lambda domain=None, key=None: _name(key)

        async def _name(key):
            return "Lilian’s iPhone" if key == "DeviceName" else None

        rows = [SimpleNamespace(serial=UDID, connection_type="Network"),
                SimpleNamespace(serial=UDID.upper(), connection_type="USB")]
        device = self.device(rows, client)
        result = bridge.Bridge(self.config(), device).handle({"requestID": RID, "action": "devices"})
        self.assertEqual({item["name"] for item in result["payload"]["devices"]}, {"Lilian’s iPhone"})
        self.assertEqual(device.calls, [(UDID.upper(), "USB", False)])
        self.assertTrue(client.closed)

    def test_registered_devices_lists_the_teams_profile_phones_with_known_names(self):
        instance = bridge.Bridge(self.config(), self.device([]))
        other = "00008160-00180cc03e00000a"
        instance._profile_device_ids = lambda team: [UDID, other] if team == TEAM_ID else []
        instance._xcode_device_names = lambda: {other: "Lilian’s iPhone"}
        result = instance.handle({"requestID": RID, "action": "registeredDevices", "teamID": TEAM_ID})
        self.assertEqual(result["payload"]["devices"],
                         [{"id": UDID, "name": ""}, {"id": other, "name": "Lilian’s iPhone"}])
        with self.assertRaisesRegex(bridge.BridgeError, "invalid-request"):
            bridge._validate_request({"requestID": RID, "action": "registeredDevices"})
        with self.assertRaisesRegex(bridge.BridgeError, "invalid-request"):
            bridge._validate_request({"requestID": RID, "action": "registeredDevices", "teamID": TEAM_ID,
                                      "deviceID": UDID})

    def test_device_list_keeps_unknown_name_when_the_phone_is_not_trusted(self):
        class Untrusted(FakeDeviceModule):
            async def open_lockdown(self, serial, connection, cache, *, autopair):
                raise RuntimeError("not paired")

        rows = [SimpleNamespace(serial=UDID, connection_type="USB")]
        result = bridge.Bridge(self.config(), Untrusted(rows)).handle({"requestID": RID, "action": "devices"})
        self.assertEqual(result["payload"]["devices"][0]["name"], "")

    def test_inspect_uses_exact_usb_autopair_false_and_developer_mode(self):
        values = {"UniqueDeviceID": UDID, "ProductVersion": "27.0", "ProductType": "iPhone16,1", "DeviceName": "Test Phone"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID.upper(), connection_type="USB")], client)
        result = bridge.Bridge(self.config(), device).inspect(UDID, TARGET_BUNDLE_ID)
        self.assertEqual(device.calls, [(UDID.upper(), "USB", False)])
        self.assertEqual(result["device"]["transport"], "usb")
        self.assertEqual(result["device"]["modelName"], "iPhone16,1")
        self.assertTrue(result["developerMode"])
        self.assertIsNone(result["vpnInstalled"])

    def test_handle_reuses_one_asyncio_runner_for_open_read_and_close(self):
        values = {"UniqueDeviceID": UDID, "ProductVersion": "27.0", "DeviceName": "Test Phone"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        response = bridge.Bridge(self.config(), device).handle(
            {"requestID": RID, "action": "inspect", "deviceID": UDID, "teamID": TEAM_ID}
        )
        self.assertEqual(response["status"], "ok")
        self.assertEqual(len(client.loop_ids), 1)

    def test_vpn_installation_uses_the_actual_bundle_lookup(self):
        for apps, expected in [({}, False), ({bridge.LOCALDEVVPN_BUNDLE_ID: {}}, True), (None, None)]:
            with self.subTest(expected=expected):
                queried = []
                class Service:
                    def __init__(self, client):
                        pass
                    async def get_apps(self, *, bundle_identifiers):
                        queried.append(bundle_identifiers)
                        if apps is None:
                            raise OSError("unavailable")
                        return apps
                    async def close(self):
                        pass
                client = FakeClient({"UniqueDeviceID": UDID, "ProductVersion": "27.0"})
                device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
                module = SimpleNamespace(InstallationProxyService=Service)
                with mock.patch.dict(sys.modules, {"pymobiledevice3.services.installation_proxy": module}):
                    result = bridge.Bridge(self.config(), device).inspect(UDID, TARGET_BUNDLE_ID)
                self.assertIs(result["vpnInstalled"], expected)
                self.assertIn([bridge.LOCALDEVVPN_BUNDLE_ID], queried)
                self.assertIn([TARGET_BUNDLE_ID], queried)

    def test_missing_developer_mode_observation_remains_unknown(self):
        class MissingDeveloper(FakeClient):
            async def get_value(self, domain=None, key=None):
                if domain is not None:
                    raise RuntimeError("unsupported key")
                return self.values

        client = MissingDeveloper({"UniqueDeviceID": UDID, "ProductVersion": "27.0"})
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        result = bridge.Bridge(self.config(), device).inspect(UDID, TARGET_BUNDLE_ID)
        self.assertIsNone(result["developerMode"])

    def test_identity_mismatch_fails_closed(self):
        values = {"UniqueDeviceID": "fedcba9876543210fedcba9876543210fedcba98", "ProductVersion": "27.0"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        with self.assertRaisesRegex(bridge.BridgeError, "identity-mismatch"):
            bridge.Bridge(self.config(), device).inspect(UDID, TARGET_BUNDLE_ID)

    def test_unsupported_or_unknown_ios_stops_before_app_lookup(self):
        for version in ["25.9", None, "invalid"]:
            with self.subTest(version=version):
                client = FakeClient({"UniqueDeviceID": UDID, "ProductVersion": version})
                device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
                instance = bridge.Bridge(self.config(), device)
                with mock.patch.object(instance, "_installed_info", side_effect=AssertionError("must not query apps")):
                    response = instance.handle({"requestID": RID, "action": "inspect", "deviceID": UDID,
                                               "teamID": TEAM_ID})
                self.assertEqual(response["status"], "error")
                self.assertEqual(response["code"], "unsupported-os")
                self.assertTrue(client.closed)

    def test_stdio_response_is_single_json_object(self):
        config = self.config()
        request = json.dumps({"requestID": RID, "action": "unknown"}).encode()
        response = bridge.run_stdio(config, stdin=io.BytesIO(request))
        self.assertEqual(response["code"], "invalid-request")

    def test_bundle_layout_derives_paths_without_configuration_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            directories = [
                "Python/python/install/bin",
                "Python/python/install/lib/python3.14/site-packages",
                "Bridge/Device", "Bridge/Setup", "iOSProject/GoFly.xcodeproj", "native",
            ]
            for relative in directories:
                (root / relative).mkdir(parents=True, exist_ok=True)
            files = [
                "Bridge/bridge.py", "Bridge/wire.py", "Bridge/Device/gofly_device.py",
                "Bridge/Setup/setup_protocol.py", "Bridge/Setup/setup_config.py",
                "Bridge/Setup/setup_journal.py", "Bridge/Setup/setup_producer.py",
                "Bridge/Setup/setup_adapters.py", "Bridge/Setup/setup_support.py",
                "iOSProject/GoFly.xcodeproj/project.pbxproj", "iOSProject/GoFly.xcconfig",
                "native/libidevice_ffi.a",
            ]
            for relative in files:
                (root / relative).write_text("fixture")
            interpreter = root / "Python/python/install/bin/python3.14"
            interpreter.write_text("#!/bin/sh\nexit 0\n")
            interpreter.chmod(0o700)
            config = bridge.Config.from_bundle(root, root / "Developer")
            self.assertEqual(config.python_path, root / "Python/python/install/bin/python3.14")
            self.assertEqual(config.project_path, root / "iOSProject/GoFly.xcodeproj")
            self.assertEqual(config.state_root, Path.home() / "Library/Application Support/GoFly/state")

    def test_incomplete_bundle_has_one_stable_damage_code(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(bridge.BridgeError, "bundle-damaged"):
                bridge.Config.from_bundle(directory, Path(directory) / "Developer")

    def test_environment_returns_ordered_fresh_mac_checks_and_teams(self):
        instance = bridge.Bridge(self.config(), self.device([]))
        instance._check_xcode_installed = lambda: "passed"
        instance._xcode_version = lambda: "27.1"
        instance._macos_version = lambda: "27.0.1"
        instance._xcode_minimum_macos_version = lambda _installed: "26.6"
        instance._available_space_kib = lambda: 50 * 1024 * 1024
        instance._check_first_launch = lambda _installed: "passed"
        instance._ios_platform = lambda _installed: ("passed", "iPhoneOS27.1.sdk")
        instance._teams = lambda: [{"teamID": TEAM_ID, "teamName": "Test Team", "isFreeProvisioningTeam": True}]

        result = instance.environment()
        self.assertTrue(result["ready"])
        self.assertEqual([row["id"] for row in result["checks"]], [
            "macos-version", "available-space", "xcode-installed", "xcode-first-launch", "ios-platform", "apple-account",
        ])
        self.assertTrue(all(row["status"] == "passed" and row["passed"] for row in result["checks"]))
        self.assertEqual(result["teams"][0]["teamID"], TEAM_ID)

    def test_environment_uses_planned_xcode_minimum_and_does_not_fake_unknowns(self):
        instance = bridge.Bridge(self.config(), self.device([]))
        instance._check_xcode_installed = lambda: "failed"
        instance._macos_version = lambda: "25.5"
        instance._available_space_kib = lambda: 10 * 1024 * 1024
        instance._teams = lambda: (_ for _ in ()).throw(AssertionError("no Xcode account query"))

        result = instance.environment()
        rows = {row["id"]: row for row in result["checks"]}
        self.assertFalse(result["ready"])
        self.assertEqual(rows["macos-version"]["status"], "failed")
        self.assertIn(bridge.PLANNED_XCODE_MINIMUM_MACOS_VERSION, rows["macos-version"]["detail"])
        self.assertEqual(rows["available-space"]["status"], "failed")
        self.assertEqual(rows["xcode-installed"]["status"], "failed")
        self.assertEqual(rows["xcode-first-launch"]["status"], "unknown")
        self.assertEqual(rows["ios-platform"]["status"], "unknown")
        self.assertEqual(rows["apple-account"]["status"], "unknown")

    def test_environment_reports_unknown_when_observations_cannot_be_read(self):
        instance = bridge.Bridge(self.config(), self.device([]))
        instance._check_xcode_installed = lambda: "unknown"
        instance._macos_version = lambda: None
        instance._available_space_kib = lambda: None
        instance._xcode_minimum_macos_version = lambda _installed: None
        instance._teams = lambda: None

        result = instance.environment()
        rows = {row["id"]: row for row in result["checks"]}
        self.assertFalse(result["ready"])
        self.assertEqual(rows["macos-version"]["status"], "unknown")
        self.assertEqual(rows["macos-version"]["passed"], False)
        self.assertEqual(rows["available-space"]["status"], "unknown")
        self.assertEqual(rows["xcode-installed"]["status"], "unknown")
        self.assertEqual(rows["apple-account"]["status"], "unknown")

    def test_xcode_minimum_is_read_from_xcode_info_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            developer = root / "Xcode.app/Contents/Developer"
            developer.mkdir(parents=True)
            (developer.parent / "Info.plist").write_bytes(plistlib.dumps({"LSMinimumSystemVersion": "26.6"}))
            instance = bridge.Bridge(bridge.Config(root, root / "python", developer, root / "GoFly.xcodeproj"))
            self.assertEqual(instance._xcode_minimum_macos_version(True), "26.6")
            self.assertEqual(instance._xcode_minimum_macos_version(False), bridge.PLANNED_XCODE_MINIMUM_MACOS_VERSION)

    def test_xcode_first_launch_and_license_checks_are_read_only(self):
        instance = bridge.Bridge(self.config())
        is_file = Path.is_file

        def fake_is_file(path):
            if path == Path("/usr/bin/xcrun"):
                return True
            return is_file(path)

        with mock.patch.object(bridge.Path, "is_file", autospec=True, side_effect=fake_is_file), \
             mock.patch.object(bridge, "_safe_process", side_effect=[(0, b""), (0, b"")]) as process:
            self.assertEqual(instance._check_first_launch(True), "passed")
        self.assertEqual(process.call_count, 2)
        self.assertEqual(process.call_args_list[0].args[0], ["/usr/bin/xcrun", "xcodebuild", "-checkFirstLaunchStatus"])
        self.assertEqual(process.call_args_list[1].args[0], ["/usr/bin/xcrun", "xcodebuild", "-license", "check"])

    def test_df_available_space_parser_uses_gibibyte_blocks(self):
        output = b"Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3 1000000 100 500000 1% /Applications\n"
        with mock.patch.object(bridge.Path, "is_file", return_value=True), \
             mock.patch.object(bridge, "_safe_process", return_value=(0, output)) as process:
            self.assertEqual(bridge.Bridge(self.config())._available_space_kib(), 500000)
        self.assertEqual(process.call_args.args[0], ["/bin/df", "-Pk", "/Applications"])


if __name__ == "__main__":
    unittest.main()
