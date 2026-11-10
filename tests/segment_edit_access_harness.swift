import Foundation
struct Segment { var id: String; var start = 0.0; var end = 1.0; var text = "Old" }
struct TranscriptRow { var id: String { segment.id }; var segment: Segment; var isDescription = false }
struct SegmentEditBatch { let rows: [TranscriptRow] }
final class Studio {
    var busy = false
    var savedTranscript: [Segment] = []
    var savedCues: [Segment] = []
    func saveSegments(_ transcript: [Segment], cues: [Segment]) { savedTranscript = transcript; savedCues = cues }
}
final class Playback {
    var pending: ((Double) -> Void)?
    func pauseAndCaptureTime(_ action: @escaping (Double) -> Void) { pending = action }
    func finish() { let action = pending; pending = nil; action?(0) }
}
struct Project { var transcript = [Segment(id: "t")]; var cues = [Segment(id: "d")] }
final class EditorFixture {
    let studio = Studio(); let playback = Playback()
    var captionControlsAvailable = true; var segmentEditMode = false
    var segmentToEdit: TranscriptRow?; var segmentBatchToEdit: SegmentEditBatch?
    var project = Project()
    var transcriptRows: [TranscriptRow] { [TranscriptRow(segment: project.transcript[0]), TranscriptRow(segment: project.cues[0], isDescription: true)] }
    var selectedSegmentIDs: Set<String> = ["t", "d"]
    // PRODUCTION_METHODS
}
@main struct SegmentEditAccessHarness {
    static func main() {
        let editor = EditorFixture()
        for description in [false, true] {
            var row = TranscriptRow(segment: Segment(id: description ? "d" : "t"), isDescription: description)
            editor.presentSegmentEditor(row)
            precondition(editor.segmentToEdit == nil)
            editor.playback.finish()
            precondition(editor.segmentToEdit?.id == row.id && !editor.segmentEditMode)
            row.segment.text = "Changed"
            editor.saveEditedRows([row])
            precondition((description ? editor.studio.savedCues : editor.studio.savedTranscript).first?.text == "Changed", "View-mode single edits must persist")
            editor.segmentToEdit = nil
            editor.studio.busy = true
            editor.presentSegmentEditor(row)
            precondition(editor.playback.pending == nil)
            editor.studio.busy = false
        }
        editor.presentBulkSegmentEditor()
        precondition(editor.playback.pending == nil, "Bulk editor requires Edit mode")
        let oldText = editor.studio.savedTranscript.first?.text
        editor.saveEditedRows(editor.transcriptRows)
        precondition(editor.studio.savedTranscript.first?.text == oldText, "View mode must reject bulk saves")
        editor.segmentEditMode = true
        editor.presentBulkSegmentEditor()
        editor.segmentEditMode = false
        editor.playback.finish()
        precondition(editor.segmentBatchToEdit == nil, "Bulk presentation rechecks Edit mode")
        editor.segmentEditMode = true
        editor.presentBulkSegmentEditor()
        editor.playback.finish()
        precondition(editor.segmentBatchToEdit?.rows.count == 2)
        editor.segmentEditMode = false
        editor.presentSegmentEditor(editor.transcriptRows[0])
        editor.studio.busy = true
        editor.playback.finish()
        precondition(editor.segmentToEdit == nil, "Single presentation rechecks busy state")
        editor.studio.busy = false; editor.captionControlsAvailable = false
        editor.presentSegmentEditor(editor.transcriptRows[0])
        precondition(editor.playback.pending == nil)
        print("PASS: single view-mode edit/save, unchanged mode, bulk gates and delayed busy checks")
    }
}
