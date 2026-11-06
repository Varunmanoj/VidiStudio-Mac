"""Check real Apple voice locale lookup and provider-specific inspector labels."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    end = opening + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class NarrationVoiceLanguageTests(unittest.TestCase):
    def test_voice_metadata_not_project_language(self):
        if sys.platform != 'darwin': self.skipTest('macOS speech SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        resolver = declaration((mac / 'VidiStudio/SystemVoiceCatalog.swift').read_text(), 'enum SystemSpeechVoiceResolver')
        language = declaration((mac / 'VidiStudio/StudioModel.swift').read_text(), '@MainActor var currentNarrationLanguage: String')
        harness = '''import Foundation
import AVFoundation
@MainActor struct PiperVoiceManager {
    static let shared = Self()
    struct Voice { let languageLabel: String }
    func voice(id: String) -> Voice? { id == "en_US-test-medium" ? Voice(languageLabel: "English (United States)") : nil }
}
''' + resolver + '''
struct Settings {
    var ttsMode = "system"
    var systemVoice = ""
    var piperVoiceSignature = "en_US-test-medium"
''' + language + '''
}
@main struct Main {
    @MainActor static func main() {
        var settings = Settings()
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            settings.systemVoice = voice.identifier
            let expected = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
            precondition(settings.currentNarrationLanguage == expected)
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        precondition(!voices.isEmpty)
        for voice in voices where voice.quality == .premium {
            precondition(SystemSpeechVoiceResolver.selectedVoice(named: voice.name.hasSuffix(" (Premium)") ? voice.name : voice.name + " (Premium)")?.language == voice.language)
        }
        settings.systemVoice = "__Unavailable voice__"
        precondition(settings.currentNarrationLanguage == "Unknown")
        settings.systemVoice = ""
        if let voice = SystemSpeechVoiceResolver.selectedVoice(named: "") {
            precondition(settings.currentNarrationLanguage == (Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language))
        }
        settings.ttsMode = "piper"
        precondition(settings.currentNarrationLanguage == "English (United States)")
        settings.piperVoiceSignature = "missing"
        precondition(settings.currentNarrationLanguage == "Unknown")
        settings.ttsMode = "gemini"
        precondition(settings.currentNarrationLanguage == "Multilingual")
        print("PASS: real Apple voice locales, default, unavailable, Piper and Gemini")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / 'Main.swift').write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(folder / 'Main.swift'), '-module-cache-path', str(folder / 'modules'), '-o', str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
