import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


class BrowserRelease(unittest.TestCase):
    def test_version_bump_sync_and_release_payloads(self):
        with tempfile.TemporaryDirectory() as temp:
            mac = Path(temp) / "VidiStudio Mac"
            windows = Path(temp) / "Vidi-Studio-Windows"
            win_project = windows / "Vidi Studio Windows"
            win_project.mkdir(parents=True)
            for file in ("Vidi Studio Windows.csproj", "Package.appxmanifest"):
                shutil.copy(ROOT.parent / "Vidi-Studio-Windows" / "Vidi Studio Windows" / file, win_project)
            for folder in ("BrowserExtension", "script", "VidiStudio.xcodeproj"):
                (mac / folder).mkdir(parents=True)
            shutil.copytree(ROOT / "BrowserExtension", mac / "BrowserExtension", dirs_exist_ok=True)
            shutil.copy(ROOT / "VidiStudio.xcodeproj/project.pbxproj", mac / "VidiStudio.xcodeproj")
            shutil.copy(ROOT / "script/package_browser_extension.py", mac / "script")
            manifest_path = mac / "BrowserExtension/manifest.json"
            sync = [sys.executable, ROOT / "script/sync_version.py", "--mac-root", mac, "--windows-root", windows]
            subprocess.run([*sync, "--bump"], check=True, capture_output=True)
            manifest = json.loads(manifest_path.read_text())
            self.assertNotEqual(manifest["version"], json.loads((ROOT / "BrowserExtension/manifest.json").read_text())["version"])
            manifest_path.write_text(json.dumps(dict(manifest, version="0.0.1")))
            self.assertNotEqual(subprocess.run([*sync, "--check"], capture_output=True).returncode, 0)
            subprocess.run([*sync, "--sync"], check=True, capture_output=True)
            self.assertEqual(json.loads(manifest_path.read_text()), manifest)
            package = [sys.executable, mac / "script/package_browser_extension.py"]
            safari = mac / "safari"
            output = mac / "dist/browser-extensions"
            output.mkdir(parents=True)
            unrelated = output / "Other-Chrome-1.0.0.zip"
            unrelated.write_bytes(b"unrelated")
            for browser in ("Chrome", "Edge"):
                for old_name in ("Open-in-VidiStudio", "Describe-with-Vidi-Studio"):
                    (output / f"{old_name}-{browser}-1.0.343.zip").write_bytes(b"old release")
            subprocess.run(package, check=True, capture_output=True)
            subprocess.run(package, check=True, capture_output=True)
            self.assertEqual(unrelated.read_bytes(), b"unrelated")
            self.assertEqual({p.name for p in output.iterdir()}, {
                unrelated.name, "Describe-with-Vidi-Studio-Chrome.zip", "Describe-with-Vidi-Studio-Edge.zip"
            })
            subprocess.run([*package, "--safari-resources", safari], check=True, capture_output=True)
            zips = list(output.glob("Describe-with-Vidi-Studio-*.zip"))
            self.assertEqual(len(zips), 2)
            with (ROOT / "Config/SafariExtension-Info.plist").open("rb") as f:
                self.assertEqual(plistlib.load(f)["CFBundleDisplayName"], manifest["name"])
            self.assertEqual(manifest["name"], "Describe with Vidi Studio")
            self.assertEqual(manifest["action"]["default_title"], manifest["name"])
            for archive in zips:
                with ZipFile(archive) as z:
                    self.assertEqual(json.loads(z.read("manifest.json")), manifest)
                    for name in z.namelist():
                        self.assertEqual(z.read(name), (safari / name).read_bytes())
