"""Verify native saved-result menu labels survive the SwiftUI/AppKit bridge."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'darwin', 'Native menu accessibility requires AppKit')
class SavedResultMenuAccessibility(unittest.TestCase):
    def test_icon_metadata_updates_and_clears_native_menu_label(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='vidi-menu-accessibility-') as temporary:
            folder = Path(temporary)
            source = folder / 'Check.swift'
            source.write_text('''import AppKit
@main struct Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        let menu = NSMenu(title: "Saved Results")
        let item = NSMenuItem(title: "Version 7", action: nil, keyEquivalent: "")
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.accessibilityDescription = "Saved result status: Selected, All AD segments have audio, Export ready"
        item.image = image
        menu.addItem(item)
        NativeMenuIcons.apply(to: menu)
        precondition(item.accessibilityLabel() == "Version 7, Selected, All AD segments have audio, Export ready")
        image.accessibilityDescription = "Saved result status: Export ready"
        NativeMenuIcons.apply(to: menu)
        precondition(item.accessibilityLabel() == "Version 7, Export ready")
        image.accessibilityDescription = "Saved result status: "
        NativeMenuIcons.apply(to: menu)
        precondition(item.accessibilityLabel() == "Version 7")
        item.image = nil
        item.toolTip = "Saved result status: Selected"
        NativeMenuIcons.apply(to: menu)
        precondition(item.accessibilityLabel() == "Version 7, Selected")
        let unrelated = NSMenuItem(title: "Ordinary action", action: nil, keyEquivalent: "")
        let originalLabel = unrelated.accessibilityLabel()
        menu.addItem(unrelated)
        NativeMenuIcons.apply(to: menu)
        precondition(unrelated.accessibilityLabel() == originalLabel)
    }
}
''')
            compile_result = subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder/'modules'),
                str(root/'VidiStudio/NativeMenuIcons.swift'), str(source), '-o', str(folder/'check')],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout+compile_result.stderr)
            result = subprocess.run([str(folder/'check')], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def test_deletion_languages_include_drafts_and_exports_but_not_unused_languages(self):
        root = Path(__file__).resolve().parents[1]
        source = (root/'VidiStudio/LanguageResults.swift').read_text()
        start = source.index('    var deletionLanguages: [String]')
        end = source.index('    var resultLanguages:', start)
        property_source = source[start:end]
        fixture = r"""import Foundation
struct Result { let language: String }
struct Provenance { var languages: [String]?; let language: String }
struct OutputLanguage { static func title(_ code: String) -> String { code } }
struct Project {
    var savedLanguageResults: [Result] = []
    var exports: [String] = []
    var exportResults: [String: Provenance]? = [:]
PROPERTY
}
var p = Project()
precondition(p.deletionLanguages.isEmpty)
p.savedLanguageResults = [Result(language: "hi"), Result(language: "hi"), Result(language: "ta")]
precondition(Set(p.deletionLanguages) == ["hi", "ta"])
p.exports = ["exports/bilingual.mp4", "exports/legacy.wav"]
p.exportResults = ["exports/bilingual.mp4": Provenance(languages: ["hi", "en"], language: "hi"),
                   "exports/stale.mp4": Provenance(languages: nil, language: "fr")]
precondition(Set(p.deletionLanguages) == ["auto", "hi", "ta", "en"])
p.savedLanguageResults = []
p.exports = ["exports/bilingual.mp4"]
precondition(Set(p.deletionLanguages) == ["hi", "en"])
p.exports = []
precondition(p.deletionLanguages.isEmpty)
""".replace('PROPERTY', property_source)
        with tempfile.TemporaryDirectory(prefix='vidi-deletion-languages-') as temporary:
            folder = Path(temporary)
            swift = folder/'Check.swift'; swift.write_text(fixture)
            result = subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder/'modules'),
                str(swift), '-o', str(folder/'check')], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            result = subprocess.run([str(folder/'check')], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
