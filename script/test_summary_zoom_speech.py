"""Run production Summary readback with muted native Apple speech; Piper/error factories are stand-ins."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'VidiStudio/SummaryReadback.swift').read_text().split('// MARK: - Selectable text view')[0]
stubs = r'''
// Use a silent Apple voice for this native transport/delegate integration test.
struct StudioSettings { var ttsMode = "apple" }
enum TestIssue { case speech }
enum UserFacingIssueReporter {
    static func message(for error: Error, issue: TestIssue, context: String) -> String { error.localizedDescription }
    static func speechMessage(for error: Error, issue: TestIssue, context: String) -> String { error.localizedDescription }
}
enum SystemSpeechUtterance {
    static func make(text: String, settings: StudioSettings) throws -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 0
        return utterance
    }
}
enum PiperSpeech {
    static let shared = Backend()
    static func request(text: String, settings: StudioSettings) -> String { text }
    struct Backend {
        func synthesize(_ text: String) async throws -> URL { throw CocoaError(.featureUnsupported) }
    }
}
@main struct Run {
    @MainActor static func main() async throws {
        let model = SummaryReadbackModel()
        model.configure(markdown: String(repeating: "Andy brings the inhaler to Olivia and continues walking alongside her ", count: 12) + ".", settings: StudioSettings())
        model.playFromStart()
        for _ in 0..<120 {
            if model.wordRange != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(model.isReading && model.wordRange != nil, "Apple speech did not start or report words")
        let index = model.currentIndex
        let range = model.wordRange
        let plain = model.plainText
        model.setZoom(4)
        precondition(model.isReading && !model.isPaused && model.currentIndex == index && model.wordRange == range && model.plainText == plain, "Zoom changed active speech state")
        for _ in 0..<60 {
            if model.wordRange != range { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(model.isReading && model.wordRange != range, "Speech/highlighting did not continue after zoom")
        model.pause()
        precondition(model.isPaused)
        let pausedRange = model.wordRange
        model.zoomOut(); model.setZoom(1)
        precondition(model.isPaused && model.isReading && model.wordRange == pausedRange, "Zoom resumed paused speech")
        model.play()
        precondition(model.isReading && !model.isPaused)
        model.stop()
        precondition(!model.isReading && model.wordRange == nil)
        print("PASS: production Summary readback with native muted Apple speech continues word callbacks across zoom, retains pause, resumes and stops")
    }
}
'''
build = root / 'build/summary-zoom-speech'
build.mkdir(exist_ok=True)
(build / 'main.swift').write_text(source + stubs)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build/'modules'), str(build/'main.swift'), '-o', str(build/'test')], check=True, env=env)
subprocess.run([str(build/'test')], check=True)
