import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FinderContextMenu(unittest.TestCase):
    def test_extension_target_is_embedded_and_signed(self):
        project = (ROOT / "VidiStudio.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        self.assertIn("VidiStudioFinderExtension", project)
        self.assertIn("7A20000930ABCDEF00112233", project)
        self.assertIn("VidiStudioFinderExtension.appex in Embed Foundation Extensions", project)
        build_script = (ROOT / "script" / "build_and_run.sh").read_text(encoding="utf-8")
        self.assertIn("VidiStudioFinderExtension.appex", build_script)
        self.assertIn("Config/VidiStudioFinderExtension.entitlements", build_script)

    def test_extension_declares_finder_sync_principal_class(self):
        with (ROOT / "Config" / "FinderSyncExtension-Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        extension = info["NSExtension"]
        self.assertEqual(extension["NSExtensionPointIdentifier"], "com.apple.FinderSync")
        self.assertEqual(
            extension["NSExtensionPrincipalClass"],
            "$(PRODUCT_MODULE_NAME).FinderSync",
        )

    def test_finder_extension_adds_video_context_menu_and_opens_app(self):
        source = (ROOT / "VidiStudioFinderExtension" / "FinderSync.swift").read_text(encoding="utf-8")
        for expected in (
            "FIFinderSync",
            "contextualMenuForItems",
            "Describe with Vidi Studio",
            "VidiStudioShareLink.makeURL",
            "withApplicationAt",
            "videoExtensions",
        ):
            self.assertIn(expected, source)

    def test_settings_and_help_explain_extension_enablement(self):
        settings = (ROOT / "VidiStudio" / "SettingsView.swift").read_text(encoding="utf-8")
        self.assertIn("Finder Extension Settings", settings)
        self.assertIn("FIFinderSyncController.showExtensionManagementInterface()", settings)
        help_text = (ROOT / "docs" / "help" / "projects.html").read_text(encoding="utf-8")
        self.assertIn("Describe with Vidi Studio", help_text)
        self.assertIn("Finder Extensions", help_text)


if __name__ == "__main__":
    unittest.main()
