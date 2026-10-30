import Foundation

enum SummaryOrigin { case ai, imported, manual, unknown }
struct Project {
    var summary = "Saved summary"
    var summaryOriginLabel: SummaryOrigin = .ai
}
final class Reader {
    var stops = 0
    func stop() { stops += 1 }
}
final class Studio {
    var saves: [(String, SummaryOrigin?)] = []
    func saveSummary(_ text: String, origin: SummaryOrigin?) { saves.append((text, origin)) }
}
final class Editor {
    var project = Project()
    let studio = Studio()
    let summaryReader = Reader()
    var summaryDraftText = ""
    var summaryDraftOrigin: SummaryOrigin = .unknown
    var summaryEditMode = false
    func refreshEditorShortcutActions() {}
    func toggle() { toggleSummaryEditMode() }
    // PRODUCTION_ACTIONS
}
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
let editor = Editor()
editor.toggle()
check(editor.summaryEditMode, "Pencil must enter edit mode")
check(editor.summaryReader.stops == 1, "Editing must stop Summary playback")
check(editor.summaryDraftOrigin == .ai, "Editing must load saved provenance")
editor.toggle()
check(!editor.summaryEditMode && editor.studio.saves.isEmpty, "An unchanged draft must not rewrite the project")
editor.toggle()
editor.summaryDraftOrigin = .imported
editor.toggle()
check(editor.studio.saves.count == 1, "The sole Done control must save provenance-only changes")
check(editor.studio.saves[0].1 == .imported, "The selected provenance must reach the save action")
check(editor.studio.saves[0].0 == editor.project.summary, "Provenance-only changes must preserve summary text")
editor.project.summaryOriginLabel = .manual
editor.toggle()
check(editor.summaryDraftOrigin == .manual, "A new editing session must discard stale provenance")
editor.summaryDraftText = "Updated summary"
editor.toggle()
check(editor.studio.saves.count == 2 && editor.studio.saves[1].1 == nil, "Text-only changes must retain automatic provenance handling")
editor.toggle()
editor.summaryDraftText = "Text and provenance"
editor.summaryDraftOrigin = .imported
editor.toggle()
check(editor.studio.saves.count == 3 && editor.studio.saves[2].0 == "Text and provenance" && editor.studio.saves[2].1 == .imported, "The single action must commit both draft values")
print("PASS: Summary edit/finish actions preserve text, provenance-only edits, and fresh-session state")
