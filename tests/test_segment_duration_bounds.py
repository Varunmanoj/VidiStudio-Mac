"""Exercise production timing controls/validation and video metadata formatting."""
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


class SegmentDurationBoundsTests(unittest.TestCase):
    def test_controls_keep_invalid_times_and_validation_rejects_both_segment_kinds(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/ContentView.swift').read_text()
        model = (mac / 'VidiStudio/StudioModel.swift').read_text()
        parts = [declaration(source, marker) for marker in ['private struct TimecodeInput', 'private func preciseSegmentTimecode', 'private func segmentExcerpt', 'private func segmentValidationErrors']]
        harness = '''import SwiftUI
struct Segment { var start: Double; var end: Double; var text = "Text" }
struct TranscriptRow: Identifiable { var id = "row"; var segment: Segment; var isDescription: Bool }
struct StudioProject {
    var name = "Test"; var source = "source.mp4"; var folder: URL?; var youtubeURL: String?;
    var isYouTubeURLProject = false; var duration: Double = 0; var width = 0; var height = 0; var hasAudio = false
    func url(_ path: String) -> URL? { folder?.appendingPathComponent(path) }
}
enum VidiStudioShareLink { static func youtubeVideoID(from: String) -> String? { "abcdefghijk" } }
''' + '\n'.join(parts) + '\n' + (mac / 'VidiStudio/NarrationTimeFormat.swift').read_text() + '\n' + declaration(model, 'struct ProjectVideoInformation') + '''
extension TimecodeInput {
    func seconds(_ newValue: Int) { componentBinding(divisor: 1, modulus: 60, allowed: 0...59).wrappedValue = newValue }
    func millis(_ newValue: Int) { milliseconds.wrappedValue = newValue }
}
@main struct Main {
    @MainActor static func main() throws {
        for description in [false, true] {
            var value = 9.0
            let input = TimecodeInput(label: "End time", value: Binding(get: { value }, set: { value = $0 }))
            input.seconds(11)
            precondition(value == 11, "Out-of-bounds input must remain visible")
            func errors(_ start: Double, _ end: Double) -> [String] {
                segmentValidationErrors(for: TranscriptRow(segment: Segment(start: start, end: end), isDescription: description), among: [], duration: 10)
            }
            precondition(errors(7, value).contains { $0.contains("00:00:10.000") })
            precondition(!errors(11, 9).isEmpty)
            precondition(errors(7, 10).isEmpty)
            value = 10; input.millis(1)
            precondition(value > 10 && !errors(7, value).isEmpty)
            input.millis(0); precondition(errors(7, value).isEmpty)
            precondition(!errors(7, 7).isEmpty)
        }
        var local = StudioProject()
        local.duration = 713.955
        precondition(ProjectVideoInformation(project: local).duration == "00:11:53.955")
        local.isYouTubeURLProject = true
        precondition(ProjectVideoInformation(project: local).duration == "00:11:53.955")
        local.duration = 714
        precondition(ProjectVideoInformation(project: local).duration == "00:11:54.000")
        precondition(NarrationTimeFormat.timestamp(59.9996) == "00:01:00.000")
        precondition(NarrationTimeFormat.timestamp(90061.123) == "25:01:01.123")
        print("PASS: transcript/AD timing bounds, corrected input and millisecond video durations")
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
