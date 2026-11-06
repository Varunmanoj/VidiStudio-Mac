"""Compile and exercise the production Mac project-language command bridge."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class ProjectLanguageActions(unittest.TestCase):
    def test_selection_dispatches_only_available_unsaved_safe_language_choices(self):
        if sys.platform != 'darwin': self.skipTest('macOS SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/KeyboardShortcuts.swift').read_text()
        start = source.index('final class EditorShortcutActions')
        opening = source.index('{', start); end = opening + 1; depth = 1
        while depth:
            depth += (source[end] == '{') - (source[end] == '}'); end += 1
        production = source[start:end]
        harness = '''import SwiftUI
import AppKit
struct OutputLanguage { let id: String; let title: String }
enum OnlineService { case gemini, youtube }
struct ConnectivityService { static let shared = ConnectivityService(); func available(_ service: OnlineService) -> Bool { true } }
@MainActor
''' + production + '''
@main struct Main {
    @MainActor static func main() {
        let actions = EditorShortcutActions()
        var calls: [(String, [String])] = []
        actions.handler = { _ in }; actions.available = true
        actions.languageAction = { calls.append(($0, $1)) }
        actions.viewingLanguages = [OutputLanguage(id: "auto", title: "Auto"), OutputLanguage(id: "hi", title: "Hindi")]
        actions.selectProjectLanguage("hi")
        precondition(calls.count == 1 && calls[0].0 == "select-language" && calls[0].1 == ["--language", "hi"])
        actions.viewingLanguage = "hi"
        actions.selectProjectLanguage("hi"); actions.selectProjectLanguage("unsupported")
        precondition(calls.count == 1)
        actions.hasUnsavedSummaryEdits = true; actions.selectProjectLanguage("auto"); precondition(calls.count == 1)
        actions.hasUnsavedSummaryEdits = false; actions.available = false; actions.selectProjectLanguage("auto"); precondition(calls.count == 1)
        actions.available = true; actions.handler = nil; actions.selectProjectLanguage("auto"); precondition(calls.count == 1)
        actions.handler = { _ in }; actions.viewingLanguages = []; actions.selectProjectLanguage("auto"); precondition(calls.count == 1)
        print("PASS: project language guarded dispatch")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); swift = folder / 'Main.swift'; swift.write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-module-cache-path', str(folder / 'modules'), '-o', str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
