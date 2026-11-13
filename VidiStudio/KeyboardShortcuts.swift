import SwiftUI
import AppKit

@MainActor @Observable
final class EditorShortcutActions {
    var previewHidden = false
    var isVideoFullScreen = false
    var fullScreenTitle: String { isVideoFullScreen ? "Exit Full-Screen Video" : "Full-Screen Video" }
    var timelineVisible = true
    var thumbnailImagesVisible = false
    var available = false
    var activeSection = "transcript"
    var activeSectionTitle: String {
        switch activeSection {
        case "summary": return "Summary"
        case "descriptions": return "Descriptions"
        case "ad-overview": return "AD Overview"
        case "ad-transcript": return "AD Transcript"
        default: return "Transcript"
        }
    }
    func windowTitle(projectName: String) -> String { "\(projectName) — \(activeSectionTitle)" }
    var savedResultKinds: [String] {
        switch activeSection {
        case "transcript": return ["transcript"]
        case "summary": return ["summary"]
        case "descriptions", "ad-overview": return ["descriptions", "adAudio"]
        case "ad-transcript": return ["transcript", "descriptions"]
        default: return []
        }
    }
    var savedResultsTitle: String {
        switch activeSection {
        case "transcript": return "Transcript Saved Results"
        case "summary": return "Summary Saved Results"
        case "descriptions", "ad-overview": return "Description Saved Results"
        case "ad-transcript": return "AD Transcript Saved Results"
        default: return "Saved Results"
        }
    }
    var resultProject: StudioProject?
    var viewingLanguage = "auto"
    var viewingLanguages: [OutputLanguage] = []
    var captionDisplayMode = "off"
    var hasCopyableResults = false
    var hasTranscriptText = false
    var canToggleNarration = false
    var canToggleFollow = false
    var canAddSegment = false
    var canUndoSegment = false
    var canRedoSegment = false
    var addSegmentTitle = "Add Segment"
    var segmentEditingAvailable = false
    var segmentEditMode = false
    var hasUnsavedSummaryEdits = false
    @ObservationIgnored var languageAction: ((String, [String]) -> Void)?
    @ObservationIgnored var settingsLanguageAction: ((String, [String], Bool) -> Void)?
    var canChangeLanguage: Bool { available && segmentEditMode && ["transcript", "summary", "descriptions", "ad-transcript"].contains(activeSection) && !hasUnsavedSummaryEdits }
    var segmentEditModeTitle = "Edit Segments"
    var filterTitle = "Filter Segments…"
    var sortTitle = "Sort Segments…"
    var segmentSort = "start"
    var segmentFilterActive = false
    var canFilterSegments: Bool {
        ["transcript", "descriptions", "ad-transcript"].contains(activeSection)
    }
    var segmentCount = 0
    var selectedSegmentCount = 0
    var selectedSegmentKind: String?
    var selectedSegmentHasAudio = false
    var selectedSegmentAudioReady = false
    var videoIsPlaying = false
    var videoPlaybackStarted = false
    var canJumpToTime = false
    var selectedSegmentPreviewing = false
    var segmentPreviewPaused = false

    func rowCommandVisible(_ action: String, kind: String?) -> Bool {
        guard ["transcript", "descriptions", "ad-transcript"].contains(activeSection) else { return false }
        if let kind {
            guard ["transcript", "descriptions"].contains(kind),
                  activeSection == "ad-transcript" || activeSection == kind else { return false }
        }
        let effectiveKind = kind ?? (activeSection == "ad-transcript" ? nil : activeSection)
        switch action {
        case "segment-one-edit", "segment-one-play", "segment-one-skip", "segment-one-delete": return true
        case "segment-one-preview", "segment-one-preview-stop", "segment-one-synthesize", "segment-one-rewrite", "segment-one-import-audio", "segment-one-delete-audio":
            return effectiveKind != "transcript"
        case "segment-one-reanalyze": return effectiveKind != "descriptions"
        default: return false
        }
    }

    func canRunRowCommand(_ action: String, kind: String, hasAudio: Bool, audioReady: Bool, isPreviewing: Bool = false) -> Bool {
        guard available, rowCommandVisible(action, kind: kind) else { return false }
        switch action {
        case "segment-one-play", "segment-one-skip": return !youtubeProject || ConnectivityService.shared.available(.youtube)
        case "segment-one-reanalyze", "segment-one-rewrite": return hasValidApiKey
        case "segment-one-synthesize": return !ttsUsesGemini || hasValidApiKey
        case "segment-one-preview": return audioReady || isPreviewing
        case "segment-one-preview-stop": return isPreviewing
        case "segment-one-delete-audio": return hasAudio
        default: return true
        }
    }

    func segmentCommandTitle(_ action: String, kind: String? = nil, hasAudio: Bool? = nil, isPreviewing: Bool? = nil, isPaused: Bool? = nil) -> String {
        let kind = kind ?? selectedSegmentKind ?? (activeSection == "ad-transcript" ? nil : activeSection)
        let title = kind == "descriptions" ? "Audio description" : kind == "transcript" ? "Transcript" : "Segment"
        switch action {
        case "segment-one-edit": return "Edit \(title)\(title == "Segment" ? "" : " Segment")…"
        case "segment-one-play": return "Play from \(title)"
        case "segment-one-skip": return "Skip to \(title)"
        case "segment-one-preview":
            return (isPreviewing ?? selectedSegmentPreviewing) ? ((isPaused ?? segmentPreviewPaused) ? "Resume Narration" : "Pause Narration") : "Play Narration"
        case "segment-one-preview-stop": return "Stop Narration"
        case "segment-one-synthesize": return (hasAudio ?? selectedSegmentHasAudio) ? "Regenerate Segment Narration" : "Synthesize This Segment"
        case "segment-one-rewrite": return "Rewrite to Fit"
        case "segment-one-import-audio": return "Import Narration Audio…"
        case "segment-one-delete-audio": return "Delete Segment Audio…"
        case "segment-one-reanalyze": return "Re-Analyze This Segment…"
        case "segment-one-delete": return "Delete Segment…"
        default: return action
        }
    }

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
    var hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && !aiProcessingBlocked && ConnectivityService.shared.available(.gemini) }
    var youtubeProject = false
    @ObservationIgnored var youtubeHandler: ((String) -> Void)?
    var ttsUsesGemini = false
    var isSynthesizingNarration = false
    var narratingSegmentIndex: Int? = nil
    var narratingTotalCount = 0
    /// Summary section readback state, synced by the project editor.
    var summaryActive = false
    /// True while the Markdown summary editor is active. Project List/Grid
    /// shortcuts are temporarily disabled so Command-Option-1/2 apply headings.
    var summaryEditing = false
    var summaryZoom: Double = 1

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
    var canImportOriginalAudio = false
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
    @ObservationIgnored var handler: ((String) -> Void)?
    @ObservationIgnored var copyHandler: ((Bool) -> Void)?
    @ObservationIgnored var exportHandler: (() -> Void)?

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

    func selectSavedResult(_ result: SavedLanguageResult) {
        guard canRun("saved-results"), savedResultKinds.contains(result.kind), let project = resultProject,
              project.languageResults(kind: result.kind, includingDrafts: true).contains(where: { $0.id == result.id }),
              project.activeLanguageResultID(result.kind) != result.id else { return }
        languageAction?("select-result", ["--result-id", result.id])
    }

    func selectProjectLanguage(_ code: String) {
        guard canRun("project-language"), viewingLanguages.contains(where: { $0.id == code }), code != viewingLanguage else { return }
        languageAction?("select-language", ["--language", code])
    }

    /// Visibility follows the focused editor's tab; busy/prerequisite state only disables relevant actions.
    func isCommandVisible(_ action: String) -> Bool {
        guard isCommandVisibleInMode(action) else { return false }
        if action == "stop" { return videoPlaybackStarted }
        if action.hasPrefix("segment-one-") { return segmentEditMode && rowCommandVisible(action, kind: selectedSegmentKind) && (action != "segment-one-preview-stop" || selectedSegmentPreviewing) }
        if action.hasPrefix("summary-") { return activeSection == "summary" }
        switch action {
        case "analyze": return false // Full-project analysis belongs to All Projects.
        case "transcribe", "import-transcript", "delete-transcript": return activeSection == "transcript"
        case "generate-summary", "import-summary", "delete-summary": return activeSection == "summary"
        case "generate-ad-cues", "import-descriptions", "delete-descriptions": return activeSection == "descriptions"
        case "synthesize-tts", "synthesize-changed", "review-narration-issues", "review-narration-voices", "delete-narration":
            return ["descriptions", "ad-overview", "ad-transcript"].contains(activeSection)
        case "import-ad-audio", "narration", "caption-ad-transcript":
            return ["descriptions", "ad-transcript"].contains(activeSection)
        case "add", "reanalyze-selection", "undo", "redo": return ["transcript", "descriptions"].contains(activeSection)
        case "segment-select-all", "segment-deselect-all", "segment-edit-selected", "segment-delete-selected", "follow",
             "filter-segments", "clear-segment-filter", "sort-segments", "clear-segment-sort", "sort-start", "sort-duration-asc", "sort-duration-desc", "sort-origin",
             "caption-cycle", "caption-off", "caption-transcript":
            return ["transcript", "descriptions", "ad-transcript"].contains(activeSection)
        case "copy-to", "segment-edit-mode": return ["transcript", "summary", "descriptions", "ad-transcript"].contains(activeSection)
        case "delete-current": return ["transcript", "summary", "descriptions"].contains(activeSection)
        case "youtube-captions": return youtubeProject && activeSection == "transcript"
        case "youtube-details", "youtube-refresh", "import-original-audio": return youtubeProject
        default: return true
        }
    }

    func isCommandVisibleInMode(_ action: String) -> Bool {
        if ["segment-select-all", "segment-deselect-all", "segment-edit-selected", "segment-delete-selected", "reanalyze-selection", "undo", "redo"].contains(action) {
            return segmentEditMode
        }
        if activeSection == "summary", summaryEditing {
            return !action.hasPrefix("summary-") && !["generate-summary", "import-summary", "delete-summary", "delete-current"].contains(action)
        }
        return true
    }

    var currentSectionCopyTitle: String {
        switch activeSection {
        case "transcript": return "Copy and Translate Transcript…"
        case "summary": return "Copy and Translate Summary…"
        case "descriptions", "ad-overview": return "Copy and Translate Descriptions…"
        case "ad-transcript": return "Copy and Translate AD Transcript…"
        default: return "Copy and Translate…"
        }
    }

    func copyKinds(currentSectionOnly: Bool) -> [String] {
        guard currentSectionOnly else { return ["transcript", "summary", "descriptions"] }
        switch activeSection {
        case "transcript": return ["transcript"]
        case "summary": return ["summary"]
        case "descriptions", "ad-overview": return ["descriptions"]
        case "ad-transcript": return ["transcript", "descriptions"]
        default: return []
        }
    }

    func copyCurrentSection() {
        guard canRun("copy-to") else { return }
        copyHandler?(true)
    }

    func run(_ action: String) {
        guard canRun(action) else { return }
        if action == "copy-to" { copyHandler?(false); return }
        if ["youtube-details", "youtube-refresh", "youtube-captions"].contains(action) { youtubeHandler?(action); return }
        handler?(action)
    }

    func canRun(_ action: String) -> Bool {
        guard available, handler != nil, isCommandVisible(action) else { return false }
        if ["play", "back", "forward", "jump-to-time"].contains(action), youtubeProject, !ConnectivityService.shared.available(.youtube) { return false }
        if ["youtube-details", "youtube-refresh", "youtube-captions"].contains(action) { return youtubeHandler != nil }
        if action.hasPrefix("segment-one-") {
            guard segmentEditMode, selectedSegmentCount == 1, let kind = selectedSegmentKind else { return false }
            return canRunRowCommand(action, kind: kind, hasAudio: selectedSegmentHasAudio, audioReady: selectedSegmentAudioReady, isPreviewing: selectedSegmentPreviewing)
        }
        if action.hasPrefix("summary-") { return canRunSummary(action) }
        switch action {
        case "jump-to-time": return canJumpToTime
        case "saved-results": return !hasUnsavedSummaryEdits && resultProject?.savedLanguageResults.contains { $0.language == viewingLanguage && savedResultKinds.contains($0.kind) } == true
        case "project-language": return !hasUnsavedSummaryEdits && !viewingLanguages.isEmpty
        case "copy-to": return hasCopyableResults && !hasUnsavedSummaryEdits
        case "delete-project", "delete-content": return !hasUnsavedSummaryEdits
        case "language-results", "rename-project", "trash-project", "import-assets", "import-transcript", "import-summary", "import-descriptions", "import-ad-audio": return true
        case "import-original-audio": return canImportOriginalAudio
        case "clear-segment-filter": return canFilterSegments && segmentFilterActive
        case "clear-segment-sort": return canFilterSegments && segmentSort != "start"
        case "filter-segments", "sort-segments", "sort-start", "sort-duration-asc", "sort-duration-desc", "sort-origin":
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
        case "segment-delete-selected": return selectedSegmentCount > 0
        case "segment-deselect-all", "segment-edit-selected":
            return segmentEditMode && selectedSegmentCount > 0
        case "caption-cycle": return captionControlsAvailable && (hasTranscriptText || hasDescriptions)
        case "caption-off": return captionControlsAvailable
        case "caption-transcript": return captionControlsAvailable && hasTranscriptText
        case "caption-ad-transcript": return captionControlsAvailable && (hasTranscriptText || hasDescriptions)
        case "prepare-video": return !youtubeProject || ConnectivityService.shared.available(.youtube)
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
        guard available, handler != nil, summaryActive, !summaryEditing, summaryReadable else { return false }
        if action == "summary-zoom-in" { return summaryZoom < 4 }
        if action == "summary-zoom-out" { return summaryZoom > 0.5 }
        if action == "summary-zoom-reset" { return true }
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
        case "jump-to-time": return "clock"
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
        case "summary-zoom-in": return "plus.magnifyingglass"
        case "summary-zoom-out": return "minus.magnifyingglass"
        case "summary-zoom-reset": return "1.magnifyingglass"
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
    static let youtube: [StudioShortcut] = [
        .init(id: "youtube-browser", title: "My YouTube Videos…", key: "y", modifiers: [.command, .option], spoken: "Command + Option + Y", group: "YouTube"),
        .init(id: "youtube-accounts", title: "YouTube Accounts…", key: "y", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + Y", group: "YouTube"),
        .init(id: "youtube-open-editor", title: "Open in Editor", key: .return, modifiers: [.command], spoken: "Command + Return", group: "YouTube"),
        .init(id: "youtube-open-browser", title: "Open in YouTube", key: .return, modifiers: [.command, .shift], spoken: "Command + Shift + Return", group: "YouTube"),
        .init(id: "youtube-refresh-list", title: "Refresh Videos", key: "r", modifiers: [.command], spoken: "Command + R", group: "YouTube"),
        .init(id: "youtube-load-videos", title: "Load More Videos", key: "l", modifiers: [.command, .option], spoken: "Command + Option + L", group: "YouTube"),
        .init(id: "youtube-load-playlists", title: "Load More Playlists", key: "l", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + L", group: "YouTube")
    ]
    static let editor: [StudioShortcut] = [
        .init(id: "export", title: "Export…", key: "e", modifiers: [.command, .shift], spoken: "Command + Shift + E", group: "File"),
        .init(id: "preview", title: "Show or Hide Preview", key: "v", modifiers: [.command, .shift], spoken: "Command + Shift + V", group: "Playback"),
        .init(id: "fullscreen", title: "Full-Screen Video", key: "f", modifiers: [.command, .option], spoken: "Command + Option + F; Escape to return", group: "Playback"),
        .init(id: "play", title: "Play or Pause", key: .space, modifiers: [.command, .shift], spoken: "Command + Shift + Space", group: "Playback"),
        .init(id: "stop", title: "Stop Video", key: ".", modifiers: [.command, .shift], spoken: "Command + Shift + Period", group: "Playback"),
        .init(id: "back", title: "Rewind 5 Seconds", key: .leftArrow, modifiers: [.command, .option], spoken: "Command + Option + Left Arrow", group: "Playback"),
        .init(id: "forward", title: "Fast Forward 5 Seconds", key: .rightArrow, modifiers: [.command, .option], spoken: "Command + Option + Right Arrow", group: "Playback"),
        .init(id: "jump-to-time", title: "Jump to Time…", key: "j", modifiers: [.command, .shift], spoken: "Command + Shift + J", group: "Playback"),
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
        .init(id: "summary-zoom-in", title: "Zoom In", key: "=", modifiers: .command, spoken: "Command + Equals", group: "Summary Zoom"),
        .init(id: "summary-zoom-out", title: "Zoom Out", key: "-", modifiers: .command, spoken: "Command + Minus", group: "Summary Zoom"),
        .init(id: "summary-zoom-reset", title: "Actual Size (100%)", key: "0", modifiers: .command, spoken: "Command + 0", group: "Summary Zoom"),
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
    let studio: StudioModel
    @FocusedValue(\.youtubeBrowser) private var youtubeBrowser
    @FocusedValue(\.projectBrowser) private var browser
    @FocusedValue(\.editorShortcuts) private var editor
    @FocusedValue(\.allProjects) private var allProjects

    private func canRunProject(_ action: String) -> Bool {
        allProjects?.canRun(action) ?? (editor?.canRun(action) == true)
    }
    private func runProject(_ action: String) {
        if let allProjects { allProjects.run(action) } else { editor?.run(action) }
    }

    @ViewBuilder private func libraryLanguageMenu() -> some View {
        Menu("Filter Projects by Language", systemImage: "translate") {
            if let allProjects {
                Toggle("All Languages", isOn: Binding(get: { allProjects.languageFilter.wrappedValue == "all" }, set: { if $0 { allProjects.languageFilter.wrappedValue = "all" } }))
                ForEach(allProjects.languageOptions) { language in
                    Toggle(language.title, isOn: Binding(get: { allProjects.languageFilter.wrappedValue == language.id }, set: { if $0, allProjects.languageOptions.contains(language) { allProjects.languageFilter.wrappedValue = language.id } }))
                }
            }
        }.accessibilityIdentifier("projects-language-filter")
    }
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ViewBuilder private func projectLanguageMenu() -> some View {
        Menu("Project Language") {
            ForEach(editor?.viewingLanguages ?? []) { language in
                Toggle(language.title, isOn: Binding(get: { editor?.viewingLanguage == language.id }, set: { selected in
                    if selected { editor?.selectProjectLanguage(language.id) }
                }))
                .accessibilityIdentifier("project-language-" + language.id)
            }
        }
        .accessibilityIdentifier("project-language")
        .disabled(editor?.canRun("project-language") != true)
    }

    @ViewBuilder private func savedResultsMenu() -> some View {
        Menu(editor?.savedResultsTitle ?? "Saved Results") {
            if let project = editor?.resultProject {
                ForEach(editor?.savedResultKinds ?? [], id: \.self) { kind in
                    ForEach(project.languageResults(kind: kind, includingDrafts: true)) { result in
                            let option = SavedResultOption(result: result, project: project, selected: project.activeLanguageResultID(kind) == result.id, includesKind: (editor?.savedResultKinds.count ?? 0) > 1)
                            Toggle(isOn: Binding(get: { project.activeLanguageResultID(kind) == result.id }, set: { selected in
                                if selected { editor?.selectSavedResult(result) }
                            })) {
                                option
                            }.accessibilityLabel(option.spokenLabel)
                             .help("Saved result status: " + option.statusLabels.joined(separator: ", "))
                             .accessibilityIdentifier("saved-result-" + result.id)
                        }
                }
            }
        }.accessibilityIdentifier("saved-results")
         .disabled(editor?.canRun("saved-results") != true)
    }

    private var youtubeMenusVisible: Bool { allProjects != nil || editor?.youtubeProject == true || youtubeBrowser != nil }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if let allProjects {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { allProjects.run("open-gallery-window") }
                    .disabled(!allProjects.canRun("open-gallery-window"))
                Divider()
            }
            if youtubeMenusVisible {
                Button("My YouTube Videos…", systemImage: "play.rectangle") { studio.runYouTube("youtube-browser"); openWindow(id: "youtube-browser") }.keyboardShortcut("y", modifiers: [.command, .option]).disabled(studio.busy)
            }
            if youtubeMenusVisible && (youtubeBrowser != nil || browser?.canRun("youtube-open-browser") == true) {
                Button("Open in YouTube", systemImage: "arrow.up.right.square") { if youtubeBrowser != nil { youtubeBrowser?.run("youtube-open-browser") } else { browser?.run("youtube-open-browser") } }.keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(youtubeBrowser != nil ? youtubeBrowser?.canRun("youtube-open-browser") != true : browser?.canRun("youtube-open-browser") != true)
            }
            Divider()
            Button("Export…", systemImage: "square.and.arrow.up") {
                if let allProjects { allProjects.run("export") } else { editor?.showExportDialog() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(allProjects != nil ? allProjects?.canRun("export") != true : editor?.available != true || editor?.exportHandler == nil)
            Divider()
            Button("Delete Project…", systemImage: "trash", role: .destructive) { runProject("delete-project") }
                .accessibilityIdentifier("delete-project")
                .disabled(!canRunProject("delete-project"))
            Button("Choose What to Delete…", systemImage: "eraser", role: .destructive) { runProject("delete-content") }
                .accessibilityIdentifier("delete-content")
                .disabled(!canRunProject("delete-content"))
            Divider()
            Button("Remove from List", systemImage: "minus.circle") {
                browser?.run("remove-from-list")
            }
            .accessibilityIdentifier("remove-from-list")
            .disabled(browser?.canRemoveFromList != true)
            .help("Remove the selected project from this list while keeping its files in place.")
            Divider()
            Button("Settings…", systemImage: "gearshape") { openSettings() }
                .keyboardShortcut(",", modifiers: [.command])
            Button("Open Project Settings…", systemImage: "gearshape") { browser?.run("project-settings") }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                .disabled(browser?.hasProject != true || browser?.canRun("project-settings") != true)

        }
        CommandGroup(after: .sidebar) {
            if let allProjects {
                Menu("Filter Projects by Source", systemImage: "line.3.horizontal.decrease.circle") {
                    Button("All Projects", systemImage: allProjects.sourceFilter.wrappedValue == .all ? "checkmark" : "square.stack") { allProjects.run("projects-source-all") }
                    Button("Local Video Projects", systemImage: allProjects.sourceFilter.wrappedValue == .local ? "checkmark" : "film") { allProjects.run("projects-source-local") }
                    Button("YouTube Projects", systemImage: allProjects.sourceFilter.wrappedValue == .youtube ? "checkmark" : "play.rectangle") { allProjects.run("projects-source-youtube") }
                }
                libraryLanguageMenu()
                Menu("Sort Projects", systemImage: "arrow.up.arrow.down") {
                    Button("Last Opened", systemImage: allProjects.projectSort.wrappedValue == .lastOpened ? "checkmark" : "clock") { allProjects.run("projects-sort-opened") }
                    Button("Name (A–Z)", systemImage: allProjects.projectSort.wrappedValue == .name ? "checkmark" : "textformat.abc") { allProjects.run("projects-sort-name") }
                    Button("Duration (Longest First)", systemImage: allProjects.projectSort.wrappedValue == .duration ? "checkmark" : "timer") { allProjects.run("projects-sort-duration") }
                    Button("Type (Local, then YouTube)", systemImage: allProjects.projectSort.wrappedValue == .type ? "checkmark" : "film") { allProjects.run("projects-sort-type") }
                }
                Button("Reset Project Filters", systemImage: "line.3.horizontal.decrease.circle") { allProjects.run("projects-reset-filters") }
                    .disabled(!allProjects.canRun("projects-reset-filters"))
                Divider()
            }
            if allProjects == nil {
                Menu("Editor Sections", systemImage: "rectangle.split.3x1") {
                    shortcutEntries(StudioShortcut.editor.filter { ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"].contains($0.id) })
                }
                Divider()
                projectLanguageMenu()
                Divider()
                savedResultsMenu()
                Divider()
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
                Button(editor?.thumbnailImagesVisible == true ? "Hide Thumbnail Images" : "Show Thumbnail Images", systemImage: "photo.on.rectangle") {
                    editor?.run("toggle-thumbnail-images")
                }
                .disabled(editor?.canRun("toggle-thumbnail-images") != true)
                if editor?.summaryActive == true && editor?.summaryEditing != true {
                    shortcutEntries(StudioShortcut.editor.filter { $0.group == "Summary Zoom" })
                }
                if editor?.canFilterSegments == true {
                    Button(editor?.filterTitle ?? "Filter Segments…", systemImage: "line.3.horizontal.decrease.circle") {
                        editor?.run("filter-segments")
                    }
                    .disabled(editor?.canRun("filter-segments") != true)
                    if editor?.segmentFilterActive == true {
                        Button("Clear Filter", systemImage: "xmark.circle") { editor?.run("clear-segment-filter") }
                            .disabled(editor?.canRun("clear-segment-filter") != true)
                    }
                    Menu(editor?.sortTitle ?? "Sort Segments", systemImage: "arrow.up.arrow.down") {
                    if editor?.segmentSort != "start" {
                        Button("Clear Sort", systemImage: "arrow.uturn.backward") { editor?.run("clear-segment-sort") }
                            .disabled(editor?.canRun("clear-segment-sort") != true)
                    }
                    Button("Sort Options…", systemImage: "arrow.up.arrow.down") { editor?.run("sort-segments") }
                        .disabled(editor?.canRun("sort-segments") != true)
                    Divider()
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
            }
            Button("Project List View", systemImage: browser?.grid?.wrappedValue == false ? "checkmark" : "list.bullet") { browser?.grid?.wrappedValue = false; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(browser?.grid == nil || editor?.summaryEditing == true)
            Button("Project Grid View", systemImage: browser?.grid?.wrappedValue == true ? "checkmark" : "square.grid.2x2") { browser?.grid?.wrappedValue = true; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(browser?.grid == nil || editor?.summaryEditing == true)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About VidiStudio", systemImage: "info.circle") {
                SettingsSectionRequest.request("About")
                openSettings()
            }
        }
        CommandGroup(replacing: .pasteboard) { }
        CommandMenu("Edit") {
            if let allProjects {
                Button("Rename Project…", systemImage: "pencil") { allProjects.run("rename-project") }
                    .disabled(!allProjects.canRun("rename-project"))
            }
            if allProjects == nil {
                if editor?.isCommandVisible("copy-to") == true {
                    Button("Copy and Translate…", systemImage: "doc.on.doc") { editor?.run("copy-to") }
                        .accessibilityIdentifier("copy-to")
                        .disabled(editor?.canRun("copy-to") != true)
                }
                if editor?.isCommandVisible("segment-edit-mode") == true {
                    Button(editor?.segmentEditModeTitle ?? "Edit Segments", systemImage: editor?.segmentEditMode == true ? "checkmark" : "pencil") {
                        editor?.run("segment-edit-mode")
                    }
                    .accessibilityIdentifier("segment-edit-mode")
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(editor?.canRun("segment-edit-mode") != true)
                }
                if editor?.segmentEditMode == true && editor?.canFilterSegments == true {
                    Divider()
                    Button("Select All Segments", systemImage: "checkmark.square") { editor?.run("segment-select-all") }
                        .keyboardShortcut("a", modifiers: [.command, .option])
                        .disabled(editor?.canRun("segment-select-all") != true)
                    Button("Deselect All Segments", systemImage: "square") { editor?.run("segment-deselect-all") }
                        .keyboardShortcut("u", modifiers: [.command, .option, .shift])
                        .disabled(editor?.canRun("segment-deselect-all") != true)
                    Divider()
                    if editor?.isCommandVisible("segment-one-edit") == true {
                        Button(editor?.segmentCommandTitle("segment-one-edit") ?? "Segment", systemImage: "pencil") { editor?.run("segment-one-edit") }
                            .accessibilityIdentifier("segment-one-edit")
                            .disabled(editor?.canRun("segment-one-edit") != true)
                    }
                    if editor?.isCommandVisible("segment-one-play") == true {
                        Button(editor?.segmentCommandTitle("segment-one-play") ?? "Segment", systemImage: "play.fill") { editor?.run("segment-one-play") }
                            .accessibilityIdentifier("segment-one-play")
                            .disabled(editor?.canRun("segment-one-play") != true)
                    }
                    if editor?.isCommandVisible("segment-one-skip") == true {
                        Button(editor?.segmentCommandTitle("segment-one-skip") ?? "Segment", systemImage: "forward.end.fill") { editor?.run("segment-one-skip") }
                            .accessibilityIdentifier("segment-one-skip")
                            .disabled(editor?.canRun("segment-one-skip") != true)
                    }
                    if editor?.isCommandVisible("segment-one-synthesize") == true {
                        Button(editor?.segmentCommandTitle("segment-one-synthesize") ?? "Segment", systemImage: "waveform") { editor?.run("segment-one-synthesize") }
                            .accessibilityIdentifier("segment-one-synthesize")
                            .disabled(editor?.canRun("segment-one-synthesize") != true)
                    }
                    if editor?.isCommandVisible("segment-one-rewrite") == true {
                        Button(editor?.segmentCommandTitle("segment-one-rewrite") ?? "Segment", systemImage: "sparkles") { editor?.run("segment-one-rewrite") }
                            .accessibilityIdentifier("segment-one-rewrite")
                            .disabled(editor?.canRun("segment-one-rewrite") != true)
                    }
                    if editor?.isCommandVisible("segment-one-import-audio") == true {
                        Button(editor?.segmentCommandTitle("segment-one-import-audio") ?? "Segment", systemImage: "square.and.arrow.down") { editor?.run("segment-one-import-audio") }
                            .accessibilityIdentifier("segment-one-import-audio")
                            .disabled(editor?.canRun("segment-one-import-audio") != true)
                    }
                    if editor?.isCommandVisible("segment-one-delete-audio") == true {
                        Button(editor?.segmentCommandTitle("segment-one-delete-audio") ?? "Segment", systemImage: "speaker.slash") { editor?.run("segment-one-delete-audio") }
                            .accessibilityIdentifier("segment-one-delete-audio")
                            .disabled(editor?.canRun("segment-one-delete-audio") != true)
                    }
                    if editor?.isCommandVisible("segment-one-reanalyze") == true {
                        Button(editor?.segmentCommandTitle("segment-one-reanalyze") ?? "Segment", systemImage: "sparkles") { editor?.run("segment-one-reanalyze") }
                            .accessibilityIdentifier("segment-one-reanalyze")
                            .disabled(editor?.canRun("segment-one-reanalyze") != true)
                    }
                    Button("Delete Selected Segments…", systemImage: "trash", role: .destructive) { editor?.run("segment-delete-selected") }
                        .accessibilityIdentifier("segment-delete-selected")
                        .disabled(editor?.canRun("segment-delete-selected") != true)
                }
            }
        }
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        if allProjects == nil {
            CommandMenu("Playback") {
                if editor?.isCommandVisible("segment-one-preview") == true {
                    Menu("Segment Narration", systemImage: "speaker.wave.2") {
                        Button(editor?.segmentCommandTitle("segment-one-preview") ?? "Play Narration", systemImage: editor?.selectedSegmentPreviewing == true && editor?.segmentPreviewPaused != true ? "pause.circle" : "play.circle") { editor?.run("segment-one-preview") }
                            .accessibilityIdentifier("segment-one-preview")
                            .disabled(editor?.canRun("segment-one-preview") != true)
                        if editor?.isCommandVisible("segment-one-preview-stop") == true {
                            Button(editor?.segmentCommandTitle("segment-one-preview-stop") ?? "Stop Narration", systemImage: "stop.circle") { editor?.run("segment-one-preview-stop") }
                                .accessibilityIdentifier("segment-one-preview-stop")
                                .disabled(editor?.canRun("segment-one-preview-stop") != true)
                        }
                    }
                    Divider()
                }
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
                if editor?.summaryActive == true && editor?.summaryEditing != true {
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
            }
        }
        CommandMenu("Project") {
            if let allProjects {
                Button("Open Selected Project", systemImage: "macwindow") { allProjects.run("open-selected-project") }
                    .disabled(!allProjects.canRun("open-selected-project"))
                Divider()
            }
            if allProjects == nil {
                Button("Language and Saved Results…", systemImage: "translate") { editor?.run("language-results") }
                    .disabled(editor?.canRun("language-results") != true)

                Menu("Editor Sections", systemImage: "rectangle.split.3x1") {
                    shortcutEntries(StudioShortcut.editor.filter { ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"].contains($0.id) })
                }
                if editor?.canFilterSegments == true {
                    Menu("Segments", systemImage: "timeline.selection") {
                        Button(editor?.segmentEditModeTitle ?? "Edit Segments", systemImage: editor?.segmentEditMode == true ? "checkmark" : "pencil") {
                            editor?.run("segment-edit-mode")
                        }
                        .keyboardShortcut("e", modifiers: [.command, .option])
                        .disabled(editor?.canRun("segment-edit-mode") != true)
                        if editor?.isCommandVisible("add") == true {
                            Button(editor?.addSegmentTitle ?? "Add Segment", systemImage: "plus") { editor?.run("add") }
                                .keyboardShortcut("n", modifiers: [.command, .shift])
                                .disabled(editor?.canRun("add") != true)
                        }
                        if editor?.segmentEditMode == true {
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
                        }
                        shortcutEntries(StudioShortcut.editor.filter { ["follow", "undo", "redo"].contains($0.id) })
                    }
                }
            }
            Menu("Analysis", systemImage: "sparkles") {
                if allProjects != nil {
                    Button("Analyze Video…", systemImage: "sparkles") { runProject("analyze") }
                        .keyboardShortcut("a", modifiers: [.command, .option, .shift])
                        .disabled(!canRunProject("analyze"))
                    Divider()
                }
                Button((!(allProjects?.project?.thumbnails.isEmpty ?? true) || editor?.hasGeneratedThumbnails == true) ? "Regenerate Video Details & Timeline Pictures…" : "Generate Video Details & Timeline Pictures", systemImage: "photo.on.rectangle.angled") { runProject("prepare-video") }
                    .disabled(!canRunProject("prepare-video"))
                if allProjects != nil || editor?.isCommandVisible("transcribe") == true {
                    Button((allProjects?.project?.hasGeneratedTranscript == true || editor?.hasGeneratedTranscript == true) ? "Regenerate Transcript…" : "Generate Transcript", systemImage: "text.bubble") { runProject("transcribe") }
                        .keyboardShortcut("t", modifiers: [.command, .option, .shift])
                        .disabled(!canRunProject("transcribe"))
                }
                if allProjects != nil || editor?.isCommandVisible("generate-summary") == true {
                    Button((allProjects?.project?.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || editor?.hasGeneratedSummary == true) ? "Regenerate Summary…" : "Generate Summary", systemImage: "text.alignleft") { runProject("generate-summary") }
                        .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                        .disabled(!canRunProject("generate-summary"))
                }
                if let allProjects {
                    Button(allProjects.project?.cues.isEmpty == false ? "Regenerate Audio Descriptions…" : "Generate Audio Descriptions", systemImage: "sparkles") { allProjects.run("generate-ad-cues") }
                    .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                        .disabled(!allProjects.canRun("generate-ad-cues"))
                }
            }
            if allProjects == nil {
                if editor?.youtubeProject == true {
                    Menu("YouTube", systemImage: "play.rectangle") {
                        Button("Video Details…", systemImage: "info.circle") { editor?.run("youtube-details") }.disabled(editor?.canRun("youtube-details") != true)
                        Button("Refresh YouTube Details", systemImage: "arrow.clockwise") { editor?.run("youtube-refresh") }.disabled(editor?.canRun("youtube-refresh") != true)
                        if editor?.isCommandVisible("youtube-captions") == true {
                            Button("Import YouTube Captions…", systemImage: "captions.bubble") { editor?.run("youtube-captions") }.disabled(editor?.canRun("youtube-captions") != true)
                        }
                    }
                }
                if editor?.isCommandVisible("synthesize-tts") == true {
                    Menu("Narration", systemImage: editor?.isSynthesizingNarration == true ? "rays" : "speaker.wave.2") {
                        if editor?.isCommandVisible("generate-ad-cues") == true {
                            Menu("AD Segment Generation", systemImage: "sparkles") {
                                Button(editor?.hasDescriptions == true ? "Regenerate Audio Descriptions…" : "Generate Audio Descriptions", systemImage: "sparkles") { editor?.run("generate-ad-cues") }
                                    .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                                    .disabled(editor?.canRun("generate-ad-cues") != true)
                                Divider()
                                Button("Delete Descriptions…", systemImage: "trash", role: .destructive) { editor?.run("delete-descriptions") }
                                    .disabled(editor?.canRun("delete-descriptions") != true)
                            }
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
                }
                if let deleteAction = editor?.currentDeleteAction, editor?.isCommandVisible(deleteAction) == true {
                    Button(editor?.currentDeleteTitle ?? "Delete Current Page…", systemImage: "trash", role: .destructive) {
                        guard let action = editor?.currentDeleteAction else { return }
                        editor?.run(action)
                    }
                    .disabled(editor?.currentDeleteAction == nil || editor?.canRun(editor?.currentDeleteAction ?? "") != true)
                }
                Divider()
                Menu("Import", systemImage: "square.and.arrow.down") {
                    if editor?.isCommandVisible("import-transcript") == true {
                        Button("Import Transcript…", systemImage: "text.bubble") { editor?.run("import-transcript") }
                            .keyboardShortcut("i", modifiers: [.command, .option])
                            .disabled(editor?.canRun("import-transcript") != true)
                    }
                    if editor?.isCommandVisible("import-summary") == true {
                        Button("Import Summary…", systemImage: "text.alignleft") { editor?.run("import-summary") }
                            .keyboardShortcut("m", modifiers: [.command, .option])
                            .disabled(editor?.canRun("import-summary") != true)
                    }
                    if editor?.isCommandVisible("import-descriptions") == true {
                        Button("Import Descriptions…", systemImage: "text.below.photo") { editor?.run("import-descriptions") }
                            .keyboardShortcut("d", modifiers: [.command, .option])
                            .disabled(editor?.canRun("import-descriptions") != true)
                    }
                    if editor?.isCommandVisible("import-original-audio") == true {
                        Button("Import Original Audio…", systemImage: "waveform") { editor?.run("import-original-audio") }
                            .disabled(editor?.canRun("import-original-audio") != true)
                    }
                    if editor?.isCommandVisible("import-ad-audio") == true {
                        Button("Import AD Audio…", systemImage: "waveform") { editor?.run("import-ad-audio") }
                            .disabled(editor?.canRun("import-ad-audio") != true)
                    }
                    Divider()
                    Button("Import Existing Assets…", systemImage: "square.and.arrow.down") { editor?.run("import-assets") }
                        .keyboardShortcut("i", modifiers: [.command, .option, .shift])
                        .disabled(editor?.canRun("import-assets") != true)
                }
            }
            Button("Show Project in Finder", systemImage: "folder") { browser?.run("show-in-finder") }
                .disabled(browser?.canRun("show-in-finder") != true)
            if studio.settings.developerMode {
                Button("Open Project Configuration", systemImage: "doc.text") { browser?.run("open-configuration") }
                    .disabled(browser?.canRun("open-configuration") != true)
            }
            Divider()
            Button("Rename Project…", systemImage: "pencil") { browser?.run("rename-project") }
                .disabled(browser?.canRun("rename-project") != true)
            Button("Move Project to Bin…", systemImage: "trash", role: .destructive) { browser?.run("trash-project") }
                .disabled(browser?.canRun("trash-project") != true)
        }
        if youtubeMenusVisible {
            CommandMenu("YouTube") {
                Button("My YouTube Videos…", systemImage: "play.rectangle") { studio.runYouTube("youtube-browser"); openWindow(id: "youtube-browser") }.keyboardShortcut("y", modifiers: [.command, .option]).disabled(studio.busy)
                Button("YouTube Accounts…", systemImage: "person.crop.circle") { youtubeBrowser?.run("youtube-accounts"); if youtubeBrowser == nil { SettingsSectionRequest.request("YouTube Accounts"); openSettings() } }
                    .keyboardShortcut("y", modifiers: [.command, .option, .shift])
                if allProjects == nil {
                Divider()
                Button("List View", systemImage: youtubeBrowser?.layout == "list" ? "checkmark" : "list.bullet") { youtubeBrowser?.run("youtube-list") }.disabled(youtubeBrowser == nil)
                Button("Table View", systemImage: youtubeBrowser?.layout == "table" ? "checkmark" : "tablecells") { youtubeBrowser?.run("youtube-table") }.disabled(youtubeBrowser == nil)
                Divider()
                Button("Open in Editor", systemImage: "pencil") { youtubeBrowser?.run("youtube-open-editor") }.keyboardShortcut(.return, modifiers: [.command]).disabled(youtubeBrowser?.canRun("youtube-open-editor") != true)
                }
                if youtubeBrowser != nil || browser?.canRun("youtube-open-browser") == true {
                    Button("Open in YouTube", systemImage: "arrow.up.right.square") { if youtubeBrowser != nil { youtubeBrowser?.run("youtube-open-browser") } else { browser?.run("youtube-open-browser") } }.keyboardShortcut(.return, modifiers: [.command, .shift]).disabled(youtubeBrowser != nil ? youtubeBrowser?.canRun("youtube-open-browser") != true : browser?.canRun("youtube-open-browser") != true)
                }
                if allProjects == nil {
                Divider()
                Button("Refresh Videos", systemImage: "arrow.clockwise") { youtubeBrowser?.run("youtube-refresh-list") }.keyboardShortcut("r", modifiers: [.command]).disabled(youtubeBrowser?.canRun("youtube-refresh-list") != true)
                Button("Load More Videos", systemImage: "plus") { youtubeBrowser?.run("youtube-load-videos") }.keyboardShortcut("l", modifiers: [.command, .option]).disabled(youtubeBrowser?.canRun("youtube-load-videos") != true)
                Button("Load More Playlists", systemImage: "plus") { youtubeBrowser?.run("youtube-load-playlists") }.keyboardShortcut("l", modifiers: [.command, .option, .shift]).disabled(youtubeBrowser?.canRun("youtube-load-playlists") != true)
                }
            }
        }
        CommandGroup(replacing: .help) {
            Button("VidiStudio Help", systemImage: "questionmark.circle") { StudioHelp.open() }.keyboardShortcut("/", modifiers: [.command, .option])
            Button("VidiStudio Website", systemImage: "arrow.up.right.square") { StudioHelp.openWebsite() }
                .accessibilityIdentifier("website")
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
        if editor?.isCommandVisible(id) == true, let shortcut = StudioShortcut.editor.first(where: { $0.id == id }) {
            Button(shortcut.title, systemImage: editor?.captionDisplayMode == mode ? "checkmark" : shortcut.icon) {
                editor?.run(shortcut.id)
            }
            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            .disabled(editor?.canRun(shortcut.id) != true)
        }
    }
    @ViewBuilder private func shortcutEntries(_ shortcuts: [StudioShortcut]) -> some View {
        ForEach(shortcuts.filter { editor?.isCommandVisible($0.id) == true }) { shortcut in
            Button(shortcut.id == "play" ? (editor?.videoIsPlaying == true ? "Pause Video" : "Play Video") : shortcut.title, systemImage: shortcut.id == "play" ? (editor?.videoIsPlaying == true ? "pause.fill" : "play.fill") : shortcut.icon) { editor?.run(shortcut.id) }
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
            Text("Keyboard Shortcuts").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1).accessibilityAddTraits(.isHeader)
            Text("These shortcuts apply to the native macOS app. Editor commands are available with a project open and no editing sheet or processing operation active.")
            Text("The File menu contains Export with Video, Audio, and Text choices. View can show or hide the preview, the complete timeline, and thumbnail images. Thumbnail images are hidden by default; the choice is remembered. The centered transport row in the timeline shares the Playback menu shortcuts for a single Play/Pause toggle, Stop Video, and five-second Rewind/Fast Forward on local and YouTube videos. Pause keeps the current position; Stop returns to the beginning and stops narration. Playback also contains Transcript Overlay controls on Transcript, Descriptions, and AD Transcript, plus Summary Reading commands that become available only on Summary. Summary Reading includes Previous and Next Sentence and Paragraph navigation, which jump to the target text and read it aloud from the centered Summary transport. Project > Segments mirrors segment editing, creation, selection, bulk editing, deletion, Follow, Undo, and Redo. Project > Analysis contains Video Details and Timeline Pictures, Analyze Video, and the individual Transcript, Summary, and Audio Description stages. The inspector stays specific to its open section. Existing content is regenerated only after confirmation.")
            shortcutRow("New Project", value: "Command + N")
            shortcutRow("Open Project Folder", value: "Command + Shift + O")
            shortcutRow("Rename Selected Project", value: "Return; All Projects")
            shortcutRow("Settings", value: "Command + Comma")
            shortcutRow("Open Project Settings", value: "Command + Shift + Comma; selected project or current editor")
            shortcutRow("Show or Hide Inspector", value: "Command + Shift + B; requires a selected project")
            shortcutRow("Show or Hide Timeline", value: "View menu; project editor")
            shortcutRow("Show or Hide Thumbnail Images", value: "View menu; hidden by default")
            shortcutRow("Project List View", value: "Command + Option + 1")
            shortcutRow("Project Grid View", value: "Command + Option + 2")
            shortcutRow("VidiStudio Help", value: "Command + Option + Slash")
            ForEach(StudioShortcut.editor + StudioShortcut.youtube) { shortcut in
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
