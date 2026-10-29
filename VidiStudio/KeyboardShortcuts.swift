import SwiftUI
import AppKit

@MainActor @Observable
final class EditorShortcutActions {
    var previewHidden = false
    var isVideoFullScreen = false
    var fullScreenTitle: String { isVideoFullScreen ? "Exit Full-Screen Video" : "Full-Screen Video" }
    var timelineVisible = true
    var available = false
    var activeSection = "transcript"
    var captionDisplayMode = "off"
    var hasTranscriptText = false
    var canToggleNarration = false
    var canToggleFollow = false
    var canAddSegment = false
    var canUndoSegment = false
    var canRedoSegment = false
    var addSegmentTitle = "Add Segment"
    var segmentEditingAvailable = false
    var segmentEditMode = false
    var segmentEditModeTitle = "Edit Segments"
    var filterTitle = "Filter Segments…"
    var sortTitle = "Sort Segments…"
    var segmentSort = "start"
    var canFilterSegments: Bool {
        ["transcript", "descriptions", "ad-transcript"].contains(activeSection)
    }
    var segmentCount = 0
    var selectedSegmentCount = 0
    var canGenerateDescriptions = false
    var hasNarrationAudio = false
    var hasDescriptions = false
    var descriptionCount = 0
    /// True when previously narrated projects have missing, changed, or failed audio to repair.
    var hasChangedNarration = false
    var hasGeneratedTranscript = false
    var hasGeneratedSummary = false
    var hasGeneratedThumbnails = false
    var hasApiKey = false
    var apiKeyVerified: Bool? = nil
    var aiProcessingBlocked = false
    var hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && !aiProcessingBlocked }
    var ttsUsesGemini = false
    var isSynthesizingNarration = false
    var narratingSegmentIndex: Int? = nil
    var narratingTotalCount = 0
    /// Summary section readback state, synced by the project editor.
    var summaryActive = false
    /// True while the Markdown summary editor is active. Project List/Grid
    /// shortcuts are temporarily disabled so Command-Option-1/2 apply headings.
    var summaryEditing = false

    var synthesizeNarrationTitle: String {
        if isSynthesizingNarration {
            if let idx = narratingSegmentIndex, narratingTotalCount > 0 {
                return "Synthesizing AD Segment \(idx) of \(narratingTotalCount)…"
            }
            return "Synthesizing Narration…"
        }
        return hasNarrationAudio ? "Regenerate All AD Audio…" : "Generate All AD Audio"
    }
    var summaryReadable = false
    var summaryIsReading = false
    var summaryIsPaused = false
    /// Sentence and paragraph navigation availability, synced by the editor.
    var summaryCanGoToPreviousSentence = false
    var summaryCanGoToNextSentence = false
    var summaryCanGoToPreviousParagraph = false
    var summaryCanGoToNextParagraph = false
    /// A text selection anchored inside the summary (read-from point).
    var summaryHasSelection = false
    /// A non-empty summary text selection (read-selection content).
    var summaryHasTextSelection = false
    var handler: ((String) -> Void)?
    var exportHandler: (() -> Void)?

    var captionControlsAvailable: Bool {
        ["transcript", "descriptions", "ad-transcript"].contains(activeSection)
    }

    var currentGenerationAction: String? {
        switch activeSection {
        case "transcript": return "transcribe"
        case "summary": return "generate-summary"
        case "descriptions": return "generate-ad-cues"
        default: return nil
        }
    }

    var currentGenerationTitle: String? {
        switch activeSection {
        case "transcript": return hasGeneratedTranscript ? "Regenerate Transcript…" : "Generate Transcript"
        case "summary": return hasGeneratedSummary ? "Regenerate Summary…" : "Generate Summary"
        case "descriptions": return hasDescriptions ? "Regenerate Audio Descriptions…" : "Generate Audio Descriptions"
        default: return nil
        }
    }

    var currentGenerationIcon: String {
        switch activeSection {
        case "transcript": return "text.bubble"
        case "summary": return "text.alignleft"
        default: return "sparkles"
        }
    }

    var currentDeleteAction: String? {
        switch activeSection {
        case "transcript": return "delete-transcript"
        case "summary": return "delete-summary"
        case "descriptions": return "delete-descriptions"
        default: return nil
        }
    }

    var currentDeleteTitle: String {
        switch activeSection {
        case "transcript": return "Delete Transcript…"
        case "summary": return "Delete Summary…"
        case "descriptions": return "Delete Descriptions…"
        default: return "Delete Current Page…"
        }
    }

    func run(_ action: String) {
        guard canRun(action) else { return }
        handler?(action)
    }

    func canRun(_ action: String) -> Bool {
        guard available, handler != nil else { return false }
        if action.hasPrefix("summary-") { return canRunSummary(action) }
        switch action {
        case "rename-project", "trash-project", "import-assets", "import-transcript", "import-summary", "import-descriptions": return true
        case "filter-segments", "sort-start", "sort-duration-asc", "sort-duration-desc", "sort-origin":
            return ["transcript", "descriptions", "ad-transcript"].contains(activeSection)
        case "narration": return canToggleNarration
        case "follow": return canToggleFollow
        case "add": return canAddSegment
        case "undo": return canUndoSegment
        case "redo": return canRedoSegment
        case "reanalyze-selection":
            guard hasValidApiKey else { return false }
            return activeSection == "transcript" || (activeSection == "descriptions" && canGenerateDescriptions)
        case "segment-edit-mode": return segmentEditingAvailable
        case "segment-select-all": return segmentEditMode && segmentCount > 0 && selectedSegmentCount < segmentCount
        case "segment-deselect-all", "segment-edit-selected", "segment-delete-selected":
            return segmentEditMode && selectedSegmentCount > 0
        case "caption-cycle": return captionControlsAvailable && (hasTranscriptText || hasDescriptions)
        case "caption-off": return captionControlsAvailable
        case "caption-transcript": return captionControlsAvailable && hasTranscriptText
        case "caption-ad-transcript": return captionControlsAvailable && (hasTranscriptText || hasDescriptions)
        case "prepare-video": return true
        case "analyze", "transcribe", "generate-summary": return hasValidApiKey
        case "generate-ad-cues": return hasValidApiKey && canGenerateDescriptions
        case "synthesize-tts":
            if ttsUsesGemini && !hasValidApiKey { return false }
            return descriptionCount > 0
        case "synthesize-changed":
            if ttsUsesGemini && !hasValidApiKey { return false }
            return hasNarrationAudio && hasChangedNarration
        case "review-narration-issues", "review-narration-voices": return true
        case "delete-transcript": return hasGeneratedTranscript
        case "delete-summary": return hasGeneratedSummary
        case "delete-descriptions": return hasDescriptions
        case "delete-narration": return hasNarrationAudio
        default: return true
        }
    }

    func showExportDialog() {
        guard available else { return }
        exportHandler?()
    }

    func canRunSummary(_ action: String) -> Bool {
        guard available, handler != nil, summaryActive, summaryReadable else { return false }
        switch action {
        case "summary-play-pause", "summary-from-start":
            return true
        case "summary-play":
            return !summaryIsReading || summaryIsPaused
        case "summary-pause":
            return summaryIsReading && !summaryIsPaused
        case "summary-from-selection":
            return summaryHasSelection
        case "summary-read-selection":
            return summaryHasTextSelection
        case "summary-previous-sentence":
            return summaryCanGoToPreviousSentence
        case "summary-next-sentence":
            return summaryCanGoToNextSentence
        case "summary-previous-paragraph":
            return summaryCanGoToPreviousParagraph
        case "summary-next-paragraph":
            return summaryCanGoToNextParagraph
        case "summary-stop":
            return summaryIsReading
        default:
            return false
        }
    }
}
private struct EditorShortcutKey: FocusedValueKey { typealias Value = EditorShortcutActions }
extension FocusedValues {
    var editorShortcuts: EditorShortcutActions? {
        get { self[EditorShortcutKey.self] }
        set { self[EditorShortcutKey.self] = newValue }
    }
}
struct StudioShortcut: Identifiable {
    let id: String
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let spoken: String
    let group: String
    var icon: String {
        switch id {
        case "preview": return "video"
        case "fullscreen": return "arrow.up.left.and.arrow.down.right"
        case "play": return "playpause"
        case "stop": return "stop.fill"
        case "back": return "gobackward.5"
        case "forward": return "goforward.5"
        case "narration": return "speaker.wave.2"
        case "caption-cycle": return "captions.bubble"
        case "caption-off": return "captions.bubble"
        case "caption-transcript": return "captions.bubble.fill"
        case "caption-ad-transcript": return "text.quote"
        case "descriptions": return "text.below.photo"
        case "transcript": return "text.bubble"
        case "summary": return "text.alignleft"
        case "ad-transcript": return "text.quote"
        case "ad-overview": return "chart.bar"
        case "add": return "plus"
        case "segment-edit-mode", "segment-edit-selected": return "square.and.pencil"
        case "segment-select-all": return "checkmark.square"
        case "segment-deselect-all": return "square"
        case "segment-delete-selected": return "trash"
        case "follow": return "text.line.first.and.arrowtriangle.forward"
        case "delete-narration": return "speaker.slash"
        case "summary-play": return "play.fill"
        case "summary-pause": return "pause.fill"
        case "summary-stop": return "stop.fill"
        case "summary-previous-sentence": return "backward.end.fill"
        case "summary-next-sentence": return "forward.end.fill"
        case "summary-previous-paragraph": return "chevron.up.2"
        case "summary-next-paragraph": return "chevron.down.2"
        case "undo": return "arrow.uturn.backward"
        case "redo": return "arrow.uturn.forward"
        case "summary-play-pause": return "playpause"
        case "export": return "square.and.arrow.up"
        case "analyze", "generate-ad-cues": return "sparkles"
        case "transcribe": return "text.bubble"
        case "generate-summary": return "text.alignleft"
        case "reanalyze-selection": return "arrow.triangle.2.circlepath"
        default: return "arrow.clockwise"
        }
    }
    static let editor: [StudioShortcut] = [
        .init(id: "export", title: "Export…", key: "e", modifiers: [.command, .shift], spoken: "Command + Shift + E", group: "File"),
        .init(id: "preview", title: "Show or Hide Preview", key: "v", modifiers: [.command, .shift], spoken: "Command + Shift + V", group: "Playback"),
        .init(id: "fullscreen", title: "Full-Screen Video", key: "f", modifiers: [.command, .option], spoken: "Command + Option + F; Escape to return", group: "Playback"),
        .init(id: "play", title: "Play or Pause", key: .space, modifiers: [.command, .shift], spoken: "Command + Shift + Space", group: "Playback"),
        .init(id: "stop", title: "Stop Video", key: ".", modifiers: [.command, .shift], spoken: "Command + Shift + Period", group: "Playback"),
        .init(id: "back", title: "Rewind 5 Seconds", key: .leftArrow, modifiers: [.command, .option], spoken: "Command + Option + Left Arrow", group: "Playback"),
        .init(id: "forward", title: "Fast Forward 5 Seconds", key: .rightArrow, modifiers: [.command, .option], spoken: "Command + Option + Right Arrow", group: "Playback"),
        .init(id: "narration", title: "Toggle Narration", key: "d", modifiers: [.command, .shift], spoken: "Command + Shift + D", group: "Playback"),
        .init(id: "caption-cycle", title: "Cycle Transcript Overlay", key: "c", modifiers: [.command, .shift], spoken: "Command + Shift + C", group: "Captions"),
        .init(id: "caption-off", title: "Turn Transcript Overlay Off", key: "0", modifiers: [.command, .control], spoken: "Command + Control + 0", group: "Captions"),
        .init(id: "caption-transcript", title: "Show Transcript Overlay", key: "1", modifiers: [.command, .control], spoken: "Command + Control + 1", group: "Captions"),
        .init(id: "caption-ad-transcript", title: "Show AD Transcript Overlay", key: "2", modifiers: [.command, .control], spoken: "Command + Control + 2", group: "Captions"),
        .init(id: "transcript", title: "Show Transcript", key: "1", modifiers: .command, spoken: "Command + 1", group: "Editor"),
        .init(id: "summary", title: "Show Summary", key: "2", modifiers: .command, spoken: "Command + 2", group: "Editor"),
        .init(id: "descriptions", title: "Show Descriptions", key: "3", modifiers: .command, spoken: "Command + 3", group: "Editor"),
        .init(id: "ad-overview", title: "Show AD Overview", key: "4", modifiers: .command, spoken: "Command + 4", group: "Editor"),
        .init(id: "ad-transcript", title: "Show AD Transcript", key: "5", modifiers: .command, spoken: "Command + 5", group: "Editor"),
        .init(id: "segment-edit-mode", title: "Enter or Leave Segment Edit Mode", key: "e", modifiers: [.command, .option], spoken: "Command + Option + E", group: "Segments"),
        .init(id: "reanalyze-selection", title: "Re-Analyze a Video Section", key: "r", modifiers: [.command, .option], spoken: "Command + Option + R", group: "Segments"),
        .init(id: "add", title: "Add Segment", key: "n", modifiers: [.command, .shift], spoken: "Command + Shift + N", group: "Segments"),
        .init(id: "segment-select-all", title: "Select All Segments", key: "a", modifiers: [.command, .option], spoken: "Command + Option + A", group: "Segments"),
        .init(id: "segment-deselect-all", title: "Deselect All Segments", key: "u", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + U", group: "Segments"),
        .init(id: "segment-edit-selected", title: "Edit Selected Segments…", key: .return, modifiers: [.command, .option], spoken: "Command + Option + Return", group: "Segments"),
        .init(id: "segment-delete-selected", title: "Delete Selected Segments…", key: .delete, modifiers: [.command, .control], spoken: "Command + Control + Delete", group: "Segments"),
        .init(id: "follow", title: "Toggle Transcript Follow", key: "f", modifiers: [.command, .shift], spoken: "Command + Shift + F", group: "Editor"),
        .init(id: "delete-narration", title: "Delete All Narration Audio…", key: .delete, modifiers: [.command, .option], spoken: "Command + Option + Delete", group: "Editor"),
        .init(id: "summary-play", title: "Play or Resume Summary Reading", key: "p", modifiers: [.command, .shift], spoken: "Command + Shift + P", group: "Summary"),
        .init(id: "summary-pause", title: "Pause Summary Reading", key: "p", modifiers: [.command, .option], spoken: "Command + Option + P", group: "Summary"),
        .init(id: "summary-stop", title: "Stop Summary Reading", key: "s", modifiers: [.command, .shift], spoken: "Command + Shift + S", group: "Summary"),
        .init(id: "summary-previous-sentence", title: "Previous Summary Sentence", key: "[", modifiers: [.command, .shift], spoken: "Command + Shift + [", group: "Summary"),
        .init(id: "summary-next-sentence", title: "Next Summary Sentence", key: "]", modifiers: [.command, .shift], spoken: "Command + Shift + ]", group: "Summary"),
        .init(id: "summary-previous-paragraph", title: "Previous Summary Paragraph", key: "[", modifiers: [.command, .option], spoken: "Command + Option + [", group: "Summary"),
        .init(id: "summary-next-paragraph", title: "Next Summary Paragraph", key: "]", modifiers: [.command, .option], spoken: "Command + Option + ]", group: "Summary"),
        .init(id: "undo", title: "Undo Segment Edit", key: "z", modifiers: [.command, .option], spoken: "Command + Option + Z", group: "Editor"),
        .init(id: "redo", title: "Redo Segment Edit", key: "z", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + Z", group: "Editor"),
        .init(id: "analyze", title: "Analyze Video…", key: "a", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + A", group: "Analysis"),
        .init(id: "transcribe", title: "Generate or Regenerate Transcript…", key: "t", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + T", group: "Analysis"),
        .init(id: "generate-summary", title: "Generate or Regenerate Summary…", key: "s", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + S", group: "Analysis"),
        .init(id: "generate-ad-cues", title: "Generate or Regenerate Audio Descriptions…", key: "d", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + D", group: "Analysis")
    ]
}
struct StudioCommands: Commands {
    @FocusedValue(\.projectBrowser) private var browser
    @FocusedValue(\.editorShortcuts) private var editor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Export…", systemImage: "square.and.arrow.up") {
                editor?.showExportDialog()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(editor?.available != true || editor?.exportHandler == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(editor?.previewHidden == true ? "Show Preview" : "Hide Preview", systemImage: editor?.previewHidden == true ? "video" : "video.slash") {
                editor?.run("preview")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editor?.canRun("preview") != true)
            Button(editor?.fullScreenTitle ?? "Full-Screen Video", systemImage: "arrow.up.left.and.arrow.down.right") {
                editor?.run("fullscreen")
            }
            .disabled(editor?.canRun("fullscreen") != true)
            Button(editor?.timelineVisible == false ? "Show Timeline" : "Hide Timeline", systemImage: "film") {
                editor?.run("toggle-timeline")
            }
            .disabled(editor?.canRun("toggle-timeline") != true)
            if editor?.canFilterSegments == true {
                Button(editor?.filterTitle ?? "Filter Segments…", systemImage: "line.3.horizontal.decrease.circle") {
                    editor?.run("filter-segments")
                }
                .disabled(editor?.canRun("filter-segments") != true)
                Menu(editor?.sortTitle ?? "Sort Segments", systemImage: "arrow.up.arrow.down") {
                Button("Start Time", systemImage: editor?.segmentSort == "start" ? "checkmark" : "clock") {
                    editor?.run("sort-start")
                }
                .disabled(editor?.canRun("sort-start") != true)
                Button("Duration — Shortest First", systemImage: editor?.segmentSort == "durationAscending" ? "checkmark" : "timer") {
                    editor?.run("sort-duration-asc")
                }
                .disabled(editor?.canRun("sort-duration-asc") != true)
                Button("Duration — Longest First", systemImage: editor?.segmentSort == "durationDescending" ? "checkmark" : "timer") {
                    editor?.run("sort-duration-desc")
                }
                .disabled(editor?.canRun("sort-duration-desc") != true)
                Button("Origin", systemImage: editor?.segmentSort == "origin" ? "checkmark" : "tag") {
                    editor?.run("sort-origin")
                }
                .disabled(editor?.canRun("sort-origin") != true)
                }
            }
            Divider()
            Button(browser?.showProjects?.wrappedValue == true ? "Hide Project List" : "Show Project List", systemImage: "sidebar.left") { browser?.showProjects?.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: .command).disabled(browser?.showProjects == nil)
            Button(browser?.hasProject == true && browser?.showInspector?.wrappedValue == true ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") { browser?.showInspector?.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(browser?.hasProject != true || browser?.showInspector == nil)
            Divider()
            Button("Project List View", systemImage: "list.bullet") { browser?.grid?.wrappedValue = false; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(browser?.grid == nil || editor?.summaryEditing == true)
            Button("Project Grid View", systemImage: "square.grid.2x2") { browser?.grid?.wrappedValue = true; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(browser?.grid == nil || editor?.summaryEditing == true)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About VidiStudio", systemImage: "info.circle") {
                SettingsSectionRequest.request("About")
                openSettings()
            }
        }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        CommandMenu("Playback") {
            shortcutEntries(StudioShortcut.editor.filter { $0.group == "Playback" })
            if editor?.captionControlsAvailable == true {
                Divider()
                Menu("Transcript Overlay: \(captionModeTitle)", systemImage: captionModeIcon) {
                    shortcutEntries(StudioShortcut.editor.filter { $0.id == "caption-cycle" })
                    Divider()
                    captionShortcutEntry("caption-off", mode: "off")
                    captionShortcutEntry("caption-transcript", mode: "transcript")
                    captionShortcutEntry("caption-ad-transcript", mode: "ad-transcript")
                }
            }
            Divider()
            Menu("Summary Reading", systemImage: "speaker.wave.2") {
                shortcutEntries(StudioShortcut.editor.filter {
                    ["summary-play", "summary-pause", "summary-stop"].contains($0.id)
                })
                Divider()
                shortcutEntries(StudioShortcut.editor.filter {
                    ["summary-previous-sentence", "summary-next-sentence",
                     "summary-previous-paragraph", "summary-next-paragraph"].contains($0.id)
                })
                Divider()
                Button("Read Summary from Start", systemImage: "forward.end") { editor?.run("summary-from-start") }
                    .disabled(editor?.canRun("summary-from-start") != true)
                Button("Read Summary from Selection", systemImage: "text.cursor") { editor?.run("summary-from-selection") }
                    .disabled(editor?.canRun("summary-from-selection") != true)
                Button("Read Selected Summary Text", systemImage: "quote.bubble") { editor?.run("summary-read-selection") }
                    .disabled(editor?.canRun("summary-read-selection") != true)
            }
            .disabled(editor?.summaryActive != true)
        }
        CommandMenu("Project") {
            Menu("Editor Sections", systemImage: "rectangle.split.3x1") {
                shortcutEntries(StudioShortcut.editor.filter { ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"].contains($0.id) })
            }
            Menu("Segments", systemImage: "timeline.selection") {
                Button(editor?.segmentEditModeTitle ?? "Edit Segments", systemImage: editor?.segmentEditMode == true ? "checkmark" : "pencil") {
                    editor?.run("segment-edit-mode")
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(editor?.canRun("segment-edit-mode") != true)
                Button(editor?.addSegmentTitle ?? "Add Segment", systemImage: "plus") { editor?.run("add") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(editor?.canRun("add") != true)
                Divider()
                shortcutEntries(StudioShortcut.editor.filter { $0.id == "reanalyze-selection" })
                Button("Select All Segments", systemImage: "checkmark.square") { editor?.run("segment-select-all") }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .disabled(editor?.canRun("segment-select-all") != true)
                Button("Deselect All Segments", systemImage: "square") { editor?.run("segment-deselect-all") }
                    .keyboardShortcut("u", modifiers: [.command, .option, .shift])
                    .disabled(editor?.canRun("segment-deselect-all") != true)
                Button("Edit Selected Segments…", systemImage: "square.and.pencil") { editor?.run("segment-edit-selected") }
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                    .disabled(editor?.canRun("segment-edit-selected") != true)
                Button("Delete Selected Segments…", systemImage: "trash", role: .destructive) { editor?.run("segment-delete-selected") }
                    .keyboardShortcut(.delete, modifiers: [.command, .control])
                    .disabled(editor?.canRun("segment-delete-selected") != true)
                Divider()
                shortcutEntries(StudioShortcut.editor.filter { ["follow", "undo", "redo"].contains($0.id) })
            }
            Menu("Analysis", systemImage: "sparkles") {
                shortcutEntries(StudioShortcut.editor.filter { $0.id == "analyze" })
                Divider()
                Button(editor?.hasGeneratedThumbnails == true ? "Regenerate Video Details & Timeline Pictures…" : "Generate Video Details & Timeline Pictures", systemImage: "photo.on.rectangle.angled") { editor?.run("prepare-video") }
                    .disabled(editor?.canRun("prepare-video") != true)
                Button(editor?.hasGeneratedTranscript == true ? "Regenerate Transcript…" : "Generate Transcript", systemImage: "text.bubble") { editor?.run("transcribe") }
                    .keyboardShortcut("t", modifiers: [.command, .option, .shift])
                    .disabled(editor?.canRun("transcribe") != true)
                Button(editor?.hasGeneratedSummary == true ? "Regenerate Summary…" : "Generate Summary", systemImage: "text.alignleft") { editor?.run("generate-summary") }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                    .disabled(editor?.canRun("generate-summary") != true)
            }
            Menu("Narration", systemImage: editor?.isSynthesizingNarration == true ? "rays" : "speaker.wave.2") {
                Menu("AD Segment Generation", systemImage: "sparkles") {
                    Button(editor?.hasDescriptions == true ? "Regenerate Audio Descriptions…" : "Generate Audio Descriptions", systemImage: "sparkles") { editor?.run("generate-ad-cues") }
                        .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                        .disabled(editor?.canRun("generate-ad-cues") != true)
                    Divider()
                    Button("Delete Descriptions…", systemImage: "trash", role: .destructive) { editor?.run("delete-descriptions") }
                        .disabled(editor?.canRun("delete-descriptions") != true)
                }
                Menu("Narration Audio", systemImage: "speaker.wave.2") {
                    Button(editor?.synthesizeNarrationTitle ?? "Generate All AD Audio", systemImage: editor?.isSynthesizingNarration == true ? "rays" : "speaker.wave.2") { editor?.run("synthesize-tts") }
                        .disabled(editor?.canRun("synthesize-tts") != true)
                    Button("Generate Missing or Changed AD Audio", systemImage: "waveform") { editor?.run("synthesize-changed") }
                        .disabled(editor?.canRun("synthesize-changed") != true)
                    Button("Review Narration Issues…", systemImage: "list.bullet.clipboard") { editor?.run("review-narration-issues") }
                        .disabled(editor?.canRun("review-narration-issues") != true)
                    Button("Review Narration Voices…", systemImage: "person.wave.2") { editor?.run("review-narration-voices") }
                        .disabled(editor?.canRun("review-narration-voices") != true)
                    Divider()
                    shortcutEntries(StudioShortcut.editor.filter { $0.id == "delete-narration" })
                }
            }
            Button(editor?.currentDeleteTitle ?? "Delete Current Page…", systemImage: "trash", role: .destructive) {
                guard let action = editor?.currentDeleteAction else { return }
                editor?.run(action)
            }
            .disabled(editor?.currentDeleteAction == nil || editor?.canRun(editor?.currentDeleteAction ?? "") != true)
            Divider()
            Menu("Import", systemImage: "square.and.arrow.down") {
                Button("Import Transcript…", systemImage: "text.bubble") { editor?.run("import-transcript") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(editor?.canRun("import-transcript") != true)
                Button("Import Summary…", systemImage: "text.alignleft") { editor?.run("import-summary") }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    .disabled(editor?.canRun("import-summary") != true)
                Button("Import Descriptions…", systemImage: "text.below.photo") { editor?.run("import-descriptions") }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .disabled(editor?.canRun("import-descriptions") != true)
                Divider()
                Button("Import Existing Assets…", systemImage: "square.and.arrow.down") { editor?.run("import-assets") }
                    .keyboardShortcut("i", modifiers: [.command, .option, .shift])
                    .disabled(editor?.canRun("import-assets") != true)
            }
            Button("Show Project in Finder", systemImage: "folder") { editor?.run("show-in-finder") }
                .disabled(editor?.canRun("show-in-finder") != true)
            Button("Open Project Configuration", systemImage: "doc.text") { editor?.run("open-configuration") }
                .disabled(editor?.canRun("open-configuration") != true)
            Divider()
            Button("Rename Project…", systemImage: "pencil") { editor?.run("rename-project") }
                .disabled(editor?.canRun("rename-project") != true)
            Button("Move Project to Bin…", systemImage: "trash", role: .destructive) { editor?.run("trash-project") }
                .disabled(editor?.canRun("trash-project") != true)
        }
        CommandGroup(replacing: .help) {
            Button("VidiStudio Help", systemImage: "questionmark.circle") { StudioHelp.open() }.keyboardShortcut("/", modifiers: [.command, .option])
        }
    }
    @ViewBuilder private func entries(_ group: String) -> some View {
        shortcutEntries(StudioShortcut.editor.filter { $0.group == group })
    }
    private var captionModeTitle: String {
        switch editor?.captionDisplayMode {
        case "transcript": return "Transcript"
        case "ad-transcript": return "AD Transcript"
        default: return "Off"
        }
    }
    private var captionModeIcon: String {
        switch editor?.captionDisplayMode {
        case "transcript": return "captions.bubble.fill"
        case "ad-transcript": return "text.quote"
        default: return "captions.bubble"
        }
    }
    @ViewBuilder private func captionShortcutEntry(_ id: String, mode: String) -> some View {
        if let shortcut = StudioShortcut.editor.first(where: { $0.id == id }) {
            Button(shortcut.title, systemImage: editor?.captionDisplayMode == mode ? "checkmark" : shortcut.icon) {
                editor?.run(shortcut.id)
            }
            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            .disabled(editor?.canRun(shortcut.id) != true)
        }
    }
    @ViewBuilder private func shortcutEntries(_ shortcuts: [StudioShortcut]) -> some View {
        ForEach(shortcuts) { shortcut in
            Button(shortcut.title, systemImage: shortcut.icon) { editor?.run(shortcut.id) }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .disabled(editor?.canRun(shortcut.id) != true)
        }
    }
}
struct ShortcutReferenceView: View {
    private func shortcutRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title): \(value)"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").font(.title2).accessibilityAddTraits(.isHeader)
            Text("These shortcuts apply to the native macOS app. Editor commands are available with a project open and no editing sheet or processing operation active.")
            Text("The File menu contains Export with Video, Audio, and Text choices. View can show or hide the preview and the complete timeline. The centered transport row beneath the thumbnails shares the Playback menu shortcuts for a single Play/Pause toggle, Stop Video, and five-second Rewind/Fast Forward on local and YouTube videos. Pause keeps the current position; Stop returns to the beginning and stops narration. Playback also contains Transcript Overlay controls on Transcript, Descriptions, and AD Transcript, plus Summary Reading commands that become available only on Summary. Summary Reading includes Previous and Next Sentence and Paragraph navigation, which jump to the target text and read it aloud from the centered Summary transport. Project > Segments mirrors segment editing, creation, selection, bulk editing, deletion, Follow, Undo, and Redo. Project > Analysis contains Video Details and Timeline Pictures, Analyze Video, and the individual Transcript, Summary, and Audio Description stages. The inspector stays specific to its open section. Existing content is regenerated only after confirmation.")
            shortcutRow("New Project", value: "Command + N")
            shortcutRow("Open Project Folder", value: "Command + Shift + O")
            shortcutRow("Rename Selected Project", value: "Return; All Projects")
            shortcutRow("Settings", value: "Command + Comma")
            shortcutRow("Show or Hide Inspector", value: "Command + Shift + B; requires a selected project")
            shortcutRow("Show or Hide Timeline", value: "View menu; project editor")
            shortcutRow("Project List View", value: "Command + Option + 1")
            shortcutRow("Project Grid View", value: "Command + Option + 2")
            shortcutRow("VidiStudio Help", value: "Command + Option + Slash")
            ForEach(StudioShortcut.editor) { shortcut in
                shortcutRow(shortcut.title, value: shortcut.spoken)
            }
            shortcutRow("Read Summary from Start", value: "Playback → Summary Reading menu; Summary section")
            shortcutRow("Read Summary from Selection", value: "Playback → Summary Reading menu, summary text right-click menu, or Play button options; needs a selection in the summary")
            shortcutRow("Read Selected Summary Text", value: "Playback → Summary Reading menu, summary text right-click menu, or Play button options; needs selected summary text")
            shortcutRow("Save Segment (in its editor)", value: "Return")
            shortcutRow("Cancel a sheet or leave full-screen video", value: "Escape")
            Text("Segment changes save when you choose Save Segment. Standard Command + Z and Command + Shift + Z remain available for text editing; the separate segment-history commands do not replace them.")
            Text("Use Tab and Shift + Tab to move between controls, Space to activate buttons and toggles, and arrow keys inside lists and pickers. Enable Keyboard navigation in macOS System Settings → Keyboard to reach all controls with Tab. VoiceOver users can use standard Control + Option navigation and interaction commands; those combinations are not assigned by VidiStudio.")
        }
    }
}
