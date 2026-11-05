"""Run production shortcut and deferred segment-presentation guards natively."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

shortcuts = (ROOT/'VidiStudio/KeyboardShortcuts.swift').read_text()
editor = (ROOT/'VidiStudio/ContentView.swift').read_text()
build = ROOT/'build/segment-edit-access-test'
build.mkdir(parents=True, exist_ok=True)
fixture = '''
@MainActor final class ConnectivityService {
    enum Service { case gemini, youtube }
    static let shared = ConnectivityService()
    func available(_ service: Service) -> Bool { true }
}
struct TranscriptRow { let id: String }
struct SegmentEditBatch { let rows: [TranscriptRow] }
@MainActor final class PlaybackFixture {
    var pending: ((Double) -> Void)?
    func pauseAndCaptureTime(_ completion: @escaping (Double) -> Void) { pending = completion }
    func finish() { let next = pending; pending = nil; next?(0) }
}
@MainActor final class StudioFixture { var busy = false }
@MainActor final class EditorFixtureState {
    var editing = false
    var row: TranscriptRow?
    var batch: SegmentEditBatch?
}
@MainActor struct EditorFixture {
    let state = EditorFixtureState()
    var segmentEditMode: Bool { get { state.editing } nonmutating set { state.editing = newValue } }
    let captionControlsAvailable = true
    let studio = StudioFixture()
    let playback = PlaybackFixture()
    var segmentToEdit: TranscriptRow? { get { state.row } nonmutating set { state.row = newValue } }
    var segmentBatchToEdit: SegmentEditBatch? { get { state.batch } nonmutating set { state.batch = newValue } }
    let transcriptRows = [TranscriptRow(id: "transcript"), TranscriptRow(id: "description")]
    let selectedSegmentIDs: Set<String> = ["transcript", "description"]
'''
actual = declaration(shortcuts, 'final class EditorShortcutActions')
actual = '@MainActor @Observable\n' + actual
for marker in ('private var canCreateSegment:', 'private var canOpenSegmentEditor:', 'private func presentSegmentEditor(', 'private func presentBulkSegmentEditor('):
    fixture += declaration(editor, marker).replace('private ', '', 1) + '\n'
production = build/'ProductionGuards.swift'
production.write_text('import SwiftUI\n' + actual + '\n' + fixture + '\n}\n')
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build/'modules'),
    str(production), str(ROOT/'tests/segment_edit_access_harness.swift'), '-o', str(build/'segment-edit-access')], check=True, env=env)
subprocess.run([str(build/'segment-edit-access')], check=True, env=env)
