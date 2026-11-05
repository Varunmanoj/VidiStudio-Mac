import Foundation

@main struct SegmentEditAccessHarness {
    @MainActor static func main() {
        let actions = EditorShortcutActions()
        var dispatched: [String] = []
        actions.available = true
        actions.handler = { dispatched.append($0) }
        actions.hasApiKey = true
        actions.apiKeyVerified = true
        actions.canGenerateDescriptions = true
        actions.canAddSegment = true
        actions.selectedSegmentCount = 1
        for section in ["transcript", "descriptions"] {
            actions.activeSection = section
            actions.segmentEditMode = false
            for command in ["add", "reanalyze-selection", "segment-edit-selected"] { actions.run(command) }
            precondition(dispatched == ["add", "reanalyze-selection"], "View mode permits additions and regeneration, but not manual edits")
            dispatched = []
            actions.segmentEditMode = true
            for command in ["add", "reanalyze-selection", "segment-edit-selected"] { actions.run(command) }
            precondition(dispatched == ["add", "reanalyze-selection", "segment-edit-selected"])
            dispatched = []
        }
        actions.segmentEditMode = false
        actions.hasGeneratedTranscript = true
        actions.hasGeneratedSummary = true
        actions.hasDescriptions = true
        let viewCommands = ["transcribe", "generate-summary", "generate-ad-cues", "delete-transcript", "delete-summary", "delete-descriptions", "segment-delete-selected"]
        for command in viewCommands { actions.run(command) }
        precondition(dispatched == viewCommands, "Generation and deletion remain available in view mode")
        dispatched = []
        actions.available = false
        actions.run("add")
        precondition(dispatched.isEmpty, "Busy or modal state must still block editors in Edit mode")
        let editor = EditorFixture()
        let row = TranscriptRow(id: "transcript")
        editor.presentSegmentEditor(row)
        editor.presentBulkSegmentEditor()
        precondition(editor.playback.pending == nil && editor.segmentToEdit == nil && editor.segmentBatchToEdit == nil)
        editor.presentSegmentEditor(row, adding: true)
        editor.playback.finish()
        precondition(editor.segmentToEdit?.id == row.id, "New drafts must open in view mode")
        editor.segmentToEdit = nil
        editor.segmentEditMode = true
        editor.presentSegmentEditor(row)
        precondition(editor.segmentToEdit == nil, "Presentation must wait for playhead capture")
        editor.segmentEditMode = false
        editor.playback.finish()
        precondition(editor.segmentToEdit == nil, "Leaving Edit mode while capturing must cancel presentation")
        editor.segmentEditMode = true
        editor.presentSegmentEditor(row)
        editor.playback.finish()
        precondition(editor.segmentToEdit?.id == row.id)
        editor.segmentToEdit = nil
        editor.presentBulkSegmentEditor()
        editor.studio.busy = true
        editor.playback.finish()
        precondition(editor.segmentBatchToEdit == nil)
        editor.studio.busy = false
        editor.presentBulkSegmentEditor()
        editor.playback.finish()
        precondition(editor.segmentBatchToEdit?.rows.count == 2)
        print("PASS: production segment-editor shortcuts, view/Edit mode gates, bulk presentation, and delayed callback cancellation")
    }
}
