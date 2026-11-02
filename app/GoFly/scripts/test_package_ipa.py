import hashlib
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from package_ipa import package


class SideStorePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "GoFly.app"
        self.app.mkdir()
        self.info = {
            "GoFlyRequiresMacSetup": True,
            "CFBundleIdentifier": "com.neven.gofly",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "CFBundleShortVersionString": "1.0.4",
            "CFBundleExecutable": "GoFly",
            "BGTaskSchedulerPermittedIdentifiers": ["com.neven.gofly.movement"],
        }
        self.write_info()
        (self.app / "GoFly").write_bytes(b"fixture executable")
        (self.app / "GoFly").chmod(0o755)

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_sideload_gate_disabled_without_changing_mac_source_or_other_metadata(self):
        original = (self.app / "Info.plist").read_bytes()
        output = package(self.app, self.root / "dist")
        self.assertEqual((self.app / "Info.plist").read_bytes(), original)
        with zipfile.ZipFile(output) as bundle:
            actual = plistlib.loads(bundle.read("Payload/GoFly.app/Info.plist"))
            self.assertIs(actual.pop("GoFlyRequiresMacSetup"), False)
            self.assertEqual(actual, {k: v for k, v in self.info.items() if k != "GoFlyRequiresMacSetup"})
            self.assertTrue(bundle.getinfo("Payload/GoFly.app/GoFly").external_attr >> 16 & 0o111)
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        self.assertEqual(output.with_suffix(".ipa.sha256").read_text(), f"{digest}  {output.name}\n")
        first = output.read_bytes()
        again = package(self.app, output.parent)
        self.assertEqual(again, output)
        archived = list((output.parent / "archive").glob("*/GoFly-1.0.4.ipa*"))
        self.assertEqual(sorted(p.name for p in archived), ["GoFly-1.0.4.ipa", "GoFly-1.0.4.ipa.sha256"])
        self.assertEqual(next(p for p in archived if p.suffix == ".ipa").read_bytes(), first)

    def test_missing_or_untyped_mac_policy_is_rejected(self):
        for value in (None, "YES", 1, False):
            with self.subTest(value=value):
                if value is None:
                    self.info.pop("GoFlyRequiresMacSetup", None)
                else:
                    self.info["GoFlyRequiresMacSetup"] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    package(self.app, self.root / "dist")

    def test_simulator_and_signed_builds_are_rejected(self):
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.write_info()
        with self.assertRaises(ValueError):
            package(self.app, self.root / "dist")
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneOS"]
        self.write_info()
        (self.app / "embedded.mobileprovision").write_bytes(b"profile")
        with self.assertRaises(ValueError):
            package(self.app, self.root / "dist")


if __name__ == "__main__":
    unittest.main()
