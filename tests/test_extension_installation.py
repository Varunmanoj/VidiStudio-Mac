import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("verify_extensions", ROOT / "script/verify_extensions.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ExtensionInstallation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "VidiStudio.app"
        self.write(self.app, MODULE.APP_ID)
        for name, (suffix, point) in MODULE.EXTENSIONS.items():
            self.write(self.app / "Contents/PlugIns" / f"{name}.appex", f"{MODULE.APP_ID}.{suffix}", point)

    def write(self, bundle, identifier, point=None, release="1.0.246", build="246"):
        path = bundle / "Contents/Info.plist"
        path.parent.mkdir(parents=True, exist_ok=True)
        data = dict(CFBundleIdentifier=identifier, CFBundleShortVersionString=release, CFBundleVersion=build)
        if point:
            data["NSExtension"] = {"NSExtensionPointIdentifier": point}
        path.write_bytes(plistlib.dumps(data))

    def test_matching_app_and_both_extensions(self):
        self.assertEqual(len(MODULE.validate_metadata(self.app)), 3)

    def test_rejects_stale_marketing_or_build_for_either_extension(self):
        for name, (suffix, point) in MODULE.EXTENSIONS.items():
            bundle = self.app / "Contents/PlugIns" / f"{name}.appex"
            for release, build in [("1.0.245", "246"), ("1.0.246", "245")]:
                with self.subTest(name=name, release=release, build=build):
                    self.write(bundle, f"{MODULE.APP_ID}.{suffix}", point, release, build)
                    with self.assertRaisesRegex(ValueError, "differs from app"):
                        MODULE.validate_metadata(self.app)
            self.write(bundle, f"{MODULE.APP_ID}.{suffix}", point)

    def test_rejects_wrong_extension_identity_and_kind(self):
        bundle = self.app / "Contents/PlugIns/VidiStudioShareExtension.appex"
        self.write(bundle, "wrong.identifier", "com.apple.share-services")
        with self.assertRaisesRegex(ValueError, "unexpected bundle identifier"):
            MODULE.validate_metadata(self.app)
        self.write(bundle, f"{MODULE.APP_ID}.ShareExtension", "com.apple.FinderSync")
        with self.assertRaisesRegex(ValueError, "unexpected extension point"):
            MODULE.validate_metadata(self.app)

    def test_rejects_missing_extension(self):
        (self.app / "Contents/PlugIns/VidiStudioShareExtension.appex/Contents/Info.plist").unlink()
        with self.assertRaises(OSError):
            MODULE.validate_metadata(self.app)
