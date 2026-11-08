"""Exercise Piper Settings selection guards and stale asynchronous completion."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class PiperSettingsPreviewTests(unittest.TestCase):
    def test_download_selection_and_cancelled_completion(self):
        if sys.platform != 'darwin': self.skipTest('macOS audio SDK required')
        root = Path(__file__).resolve().parents[1]
        source = (root / 'VidiStudio/PiperVoiceCatalog.swift').read_text()
        preview = declaration(source, '@MainActor @Observable final class PiperSettingsPreview:')
        guards = declaration(source, '    private var selectedVoice: PiperVoice?') + '\n' + declaration(source, '    private var canPlaySample: Bool')
        harness = '''import Foundation
import Observation
import AVFoundation
struct StudioSettings: Sendable {
    var ttsMode = "piper"
    var piperVoice = "downloaded"
}
struct PiperVoice { let id: String }
struct Manager {
    var downloadedVoices = [PiperVoice(id: "downloaded")]
    var deletingIDs: Set<String> = []
}
enum PiperSpeechError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
actor PiperSpeech {
    static let shared = PiperSpeech()
    struct Request: Sendable { let voice: String }
    static func request(text: String, settings: StudioSettings) -> Request { Request(voice: settings.piperVoice) }
    func synthesize(_ request: Request) async throws -> URL {
        try await Task.sleep(for: .milliseconds(40))
        throw PiperSpeechError.message("Test synthesis failure")
    }
}
''' + preview + '''
@MainActor struct Selection {
    var settings = StudioSettings()
    var manager = Manager()
    var sample = PiperSettingsPreview()
''' + guards + '''
    var canPlay: Bool { canPlaySample }
}
@main struct Main {
    @MainActor static func main() async throws {
        var selection = Selection()
        precondition(selection.canPlay)
        selection.settings.piperVoice = ""
        precondition(!selection.canPlay)
        selection.settings.piperVoice = "not-downloaded"
        precondition(!selection.canPlay)
        selection.settings.piperVoice = "downloaded"
        selection.manager.downloadedVoices = []
        precondition(!selection.canPlay)
        selection.manager.downloadedVoices = [PiperVoice(id: "downloaded")]
        selection.manager.deletingIDs = ["downloaded"]
        precondition(!selection.canPlay)
        selection.manager.deletingIDs = []
        selection.settings.ttsMode = "system"
        precondition(!selection.canPlay)
        selection.settings.ttsMode = "piper"
        precondition(selection.canPlay)
        let sample = selection.sample
        sample.play(settings: selection.settings)
        precondition(sample.active && sample.loading && !selection.canPlay)
        sample.stop()
        try await Task.sleep(for: .milliseconds(100))
        precondition(!sample.active && !sample.loading && sample.error == nil, "Cancelled synthesis must not revive playback or report stale errors")
        sample.play(settings: selection.settings)
        try await Task.sleep(for: .milliseconds(100))
        precondition(!sample.active && !sample.loading && sample.error?.contains("Test synthesis failure") == true)
        sample.play(settings: selection.settings)
        precondition(sample.error == nil)
        sample.stop()
        print("PASS: empty/uninstalled/deleting/other-engine voice guards, cancellation and synthesis failure recovery")
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            swift = folder / 'Main.swift'
            swift.write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-module-cache-path', str(folder/'modules'), '-o', str(folder/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
