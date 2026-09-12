import SwiftUI
import AppKit

@MainActor @Observable
final class EditorShortcutActions {
    var previewHidden = false
    var available = false
    var activeSection = "transcript"
    var canGenerateDescriptions = false
    var hasNarrationAudio = false
    var hasDescriptions = false
    var hasGeneratedTranscript = false
    var hasGeneratedSummary = false
    var hasLocalSource = false
    var sourceHasAudio = false
    var isYouTubeProject = false
    var exportableText: Set<String> = []
    /// Summary section readback state, synced by the project editor.
    var summaryActive = false
    var summaryReadable = false
    var summaryIsReading = false
    var summaryIsPaused = false
    /// A text selection anchored inside a summary sentence (read-from point).
    var summaryHasSelection = false
    /// A non-empty summary text selection (read-selection content).
    var summaryHasTextSelection = false
    var handler: ((String) -> Void)?
    var exportHandler: ((StudioExportAction) -> Void)?

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
        case "transcript": return hasGeneratedTranscript ? "Regenerate Transcript" : "Generate Transcript"
        case "summary": return hasGeneratedSummary ? "Regenerate Summary" : "Generate Summary"
        case "descriptions": return hasDescriptions ? "Regenerate Descriptions" : "Generate Descriptions"
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
        case "transcribe": return activeSection == "transcript"
        case "generate-summary": return activeSection == "summary"
        case "generate-ad-cues": return activeSection == "descriptions" && canGenerateDescriptions
        case "probe-video", "generate-thumbnails": return hasLocalSource
        case "extract-audio": return hasLocalSource && sourceHasAudio
        case "synthesize-tts", "synthesize-changed": return hasDescriptions
        case "delete-transcript": return hasGeneratedTranscript
        case "delete-summary": return hasGeneratedSummary
        case "delete-descriptions": return hasDescriptions
        case "delete-narration": return hasNarrationAudio
        default: return true
        }
    }

    func canExport(_ action: StudioExportAction) -> Bool {
        guard available, exportHandler != nil else { return false }
        switch action {
        case .selectableVideo, .mixedVideo:
            return !isYouTubeProject && hasLocalSource
        case .narrationAudio:
            return hasNarrationAudio
        case .text(let content, _):
            return exportableText.contains(content)
        }
    }

    func performExport(_ action: StudioExportAction) {
        guard canExport(action) else { return }
        exportHandler?(action)
    }

    func canRunSummary(_ action: String) -> Bool {
        guard available, handler != nil, summaryActive, summaryReadable else { return false }
        switch action {
        case "summary-play-pause", "summary-from-start", "summary-read-sentence",
             "summary-next", "summary-previous":
            return true
        case "summary-from-selection":
            return summaryHasSelection
        case "summary-read-selection":
            return summaryHasTextSelection
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
        case "back": return "gobackward.5"
        case "forward": return "goforward.5"
        case "narration": return "speaker.wave.2"
        case "descriptions": return "text.below.photo"
        case "transcript": return "text.bubble"
        case "summary": return "text.alignleft"
        case "ad-transcript": return "text.quote"
        case "ad-overview": return "chart.bar"
        case "add": return "plus"
        case "follow": return "text.line.first.and.arrowtriangle.forward"
        case "delete-narration": return "speaker.slash"
        case "undo": return "arrow.uturn.backward"
        case "redo": return "arrow.uturn.forward"
        case "summary-play-pause": return "playpause"
        default: return "arrow.clockwise"
        }
    }
    static let editor: [StudioShortcut] = [
        .init(id: "preview", title: "Show or Hide Preview", key: "v", modifiers: [.command, .shift], spoken: "Command + Shift + V", group: "Playback"),
        .init(id: "fullscreen", title: "Full-Screen Video", key: "f", modifiers: [.command, .option], spoken: "Command + Option + F; Escape to return", group: "Playback"),
        .init(id: "play", title: "Play or Pause", key: .space, modifiers: [.command, .shift], spoken: "Command + Shift + Space", group: "Playback"),
        .init(id: "back", title: "Seek Back 5 Seconds", key: .leftArrow, modifiers: [.command, .option], spoken: "Command + Option + Left Arrow", group: "Playback"),
        .init(id: "forward", title: "Seek Forward 5 Seconds", key: .rightArrow, modifiers: [.command, .option], spoken: "Command + Option + Right Arrow", group: "Playback"),
        .init(id: "narration", title: "Toggle Narration", key: "d", modifiers: [.command, .shift], spoken: "Command + Shift + D", group: "Playback"),
        .init(id: "transcript", title: "Show Transcript", key: "1", modifiers: .command, spoken: "Command + 1", group: "Editor"),
        .init(id: "summary", title: "Show Summary", key: "2", modifiers: .command, spoken: "Command + 2", group: "Editor"),
        .init(id: "descriptions", title: "Show Descriptions", key: "3", modifiers: .command, spoken: "Command + 3", group: "Editor"),
        .init(id: "ad-overview", title: "Show AD Overview", key: "4", modifiers: .command, spoken: "Command + 4", group: "Editor"),
        .init(id: "ad-transcript", title: "Show AD Transcript", key: "5", modifiers: .command, spoken: "Command + 5", group: "Editor"),
        .init(id: "add", title: "Add Description Segment", key: "n", modifiers: [.command, .shift], spoken: "Command + Shift + N", group: "Editor"),
        .init(id: "follow", title: "Toggle Transcript Follow", key: "f", modifiers: [.command, .shift], spoken: "Command + Shift + F", group: "Editor"),
        .init(id: "delete-narration", title: "Delete All Narration Audio…", key: .delete, modifiers: [.command, .option], spoken: "Command + Option + Delete", group: "Editor"),
        .init(id: "summary-play-pause", title: "Play or Pause Summary Reading", key: "p", modifiers: [.command, .shift], spoken: "Command + Shift + P", group: "Summary"),
        .init(id: "undo", title: "Undo Segment Edit", key: "z", modifiers: [.command, .option], spoken: "Command + Option + Z", group: "Editor"),
        .init(id: "redo", title: "Redo Segment Edit", key: "z", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + Z", group: "Editor"),
        .init(id: "analyze", title: "Run All Analysis", key: "a", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + A", group: "Analysis"),
        .init(id: "transcribe", title: "Generate / Regenerate Transcript…", key: "t", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + T", group: "Analysis"),
        .init(id: "generate-summary", title: "Generate / Regenerate Summary…", key: "s", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + S", group: "Analysis"),
        .init(id: "generate-ad-cues", title: "Generate / Regenerate Descriptions…", key: "d", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + D", group: "Analysis"),
        .init(id: "regenerate-all", title: "Regenerate All…", key: "r", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + R", group: "Analysis")
    ]
}
struct StudioCommands: Commands {
    @FocusedValue(\.projectBrowser) private var browser
    @FocusedValue(\.editorShortcuts) private var editor
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Selected Project", systemImage: "macwindow.badge.plus") {
                browser?.openSelectedProject?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(browser?.hasSelectedProject != true || browser?.openSelectedProject == nil)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Menu("Export", systemImage: "square.and.arrow.up") {
                ExportMenuContent(
                    supportsVideo: editor?.isYouTubeProject != true,
                    canPerform: { editor?.canExport($0) == true },
                    perform: { editor?.performExport($0) }
                )
            }
            .disabled(editor?.available != true)
        }
        CommandGroup(after: .sidebar) {
            Button(editor?.previewHidden == true ? "Show Preview" : "Hide Preview", systemImage: editor?.previewHidden == true ? "video" : "video.slash") {
                editor?.run("preview")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editor?.canRun("preview") != true)
            Divider()
            Button(browser?.showProjects?.wrappedValue == true ? "Hide Project List" : "Show Project List", systemImage: "sidebar.left") { browser?.showProjects?.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: .command).disabled(browser?.showProjects == nil)
            Button(browser?.hasProject == true && browser?.showInspector?.wrappedValue == true ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") { browser?.showInspector?.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(browser?.hasProject != true || browser?.showInspector == nil)
            Divider()
            Button("Project List View", systemImage: "list.bullet") { browser?.grid?.wrappedValue = false; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("1", modifiers: [.command, .option]).disabled(browser?.grid == nil)
            Button("Project Grid View", systemImage: "square.grid.2x2") { browser?.grid?.wrappedValue = true; browser?.showProjects?.wrappedValue = true }
                .keyboardShortcut("2", modifiers: [.command, .option]).disabled(browser?.grid == nil)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About VidiStudio", systemImage: "info.circle") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        CommandMenu("Playback") {
            shortcutEntries(StudioShortcut.editor.filter { $0.group == "Playback" })
            Divider()
            Menu("Summary Reading") {
                shortcutEntries(StudioShortcut.editor.filter { $0.group == "Summary" })
                Divider()
                Button("Read Summary from Start", systemImage: "forward.end") { editor?.run("summary-from-start") }
                    .disabled(editor?.canRun("summary-from-start") != true)
                Button("Read Summary from Selection", systemImage: "text.cursor") { editor?.run("summary-from-selection") }
                    .disabled(editor?.canRun("summary-from-selection") != true)
                Button("Read Selected Summary Text", systemImage: "quote.bubble") { editor?.run("summary-read-selection") }
                    .disabled(editor?.canRun("summary-read-selection") != true)
                Button("Read Current Summary Sentence", systemImage: "text.bubble") { editor?.run("summary-read-sentence") }
                    .disabled(editor?.canRun("summary-read-sentence") != true)
                Divider()
                Button("Stop Summary Reading", systemImage: "stop.fill") { editor?.run("summary-stop") }
                    .disabled(editor?.canRun("summary-stop") != true)
                Button("Previous Summary Sentence", systemImage: "backward.fill") { editor?.run("summary-previous") }
                    .disabled(editor?.canRun("summary-previous") != true)
                Button("Next Summary Sentence", systemImage: "forward.fill") { editor?.run("summary-next") }
                    .disabled(editor?.canRun("summary-next") != true)
            }
            .disabled(editor?.summaryActive != true)
        }
        CommandMenu("Project") {
            Menu("Editor Sections") {
                shortcutEntries(StudioShortcut.editor.filter { ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"].contains($0.id) })
            }
            Menu("Segments") {
                shortcutEntries(StudioShortcut.editor.filter { ["add", "follow", "undo", "redo"].contains($0.id) })
            }
            Menu("Analysis") {
                shortcutEntries(StudioShortcut.editor.filter { ["analyze", "regenerate-all"].contains($0.id) })
                Divider()
                Button(editor?.currentGenerationTitle ?? "Generate Current Page…", systemImage: editor?.currentGenerationIcon ?? "sparkles") {
                    guard let action = editor?.currentGenerationAction else { return }
                    editor?.run(action)
                }
                .keyboardShortcut(currentGenerationKey, modifiers: [.command, .option, .shift])
                .disabled(editor?.currentGenerationAction == nil || editor?.canRun(editor?.currentGenerationAction ?? "") != true)
            }
            Menu("Media Preparation") {
                Button("Read Metadata", systemImage: "info.circle") { editor?.run("probe-video") }
                    .disabled(editor?.canRun("probe-video") != true)
                Button("Generate Thumbnails", systemImage: "photo.on.rectangle") { editor?.run("generate-thumbnails") }
                    .disabled(editor?.canRun("generate-thumbnails") != true)
                Button("Extract Audio", systemImage: "waveform") { editor?.run("extract-audio") }
                    .disabled(editor?.canRun("extract-audio") != true)
            }
            Menu("Narration") {
                Button("Synthesize Narration", systemImage: "speaker.wave.2") { editor?.run("synthesize-tts") }
                    .disabled(editor?.canRun("synthesize-tts") != true)
                Button("Synthesize Changed Segments", systemImage: "waveform") { editor?.run("synthesize-changed") }
                    .disabled(editor?.canRun("synthesize-changed") != true)
                Divider()
                shortcutEntries(StudioShortcut.editor.filter { $0.id == "delete-narration" })
            }
            Button(editor?.currentDeleteTitle ?? "Delete Current Page…", systemImage: "trash", role: .destructive) {
                guard let action = editor?.currentDeleteAction else { return }
                editor?.run(action)
            }
            .disabled(editor?.currentDeleteAction == nil || editor?.canRun(editor?.currentDeleteAction ?? "") != true)
            Divider()
            Button("Show Project in Finder", systemImage: "folder") { editor?.run("show-in-finder") }
                .disabled(editor?.canRun("show-in-finder") != true)
        }
        CommandGroup(replacing: .help) {
            Button("VidiStudio Help", systemImage: "questionmark.circle") { StudioHelp.open() }.keyboardShortcut("/", modifiers: [.command, .option])
        }
    }
    @ViewBuilder private func entries(_ group: String) -> some View {
        shortcutEntries(StudioShortcut.editor.filter { $0.group == group })
    }
    private var currentGenerationKey: KeyEquivalent {
        switch editor?.activeSection {
        case "summary": return "s"
        case "descriptions": return "d"
        default: return "t"
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
            Text("The File menu contains Export with Video, Audio, and Text submenus. The Project menu groups editor sections, segment commands, current-page analysis, media preparation, and narration. Generation shortcuts use Command + Option + Shift and are enabled only on the matching editor page. Existing content is replaced only after confirmation; Regenerate All asks before deleting generated content.")
            shortcutRow("New Project", value: "Command + N")
            shortcutRow("Open Selected Project", value: "Command + O")
            shortcutRow("Open Project Folder", value: "Command + Shift + O")
            shortcutRow("Rename Selected Project", value: "Return; All Projects")
            shortcutRow("Settings", value: "Command + Comma")
            shortcutRow("Show or Hide Inspector", value: "Command + Shift + B; requires a selected project")
            shortcutRow("Project List View", value: "Command + Option + 1")
            shortcutRow("Project Grid View", value: "Command + Option + 2")
            shortcutRow("VidiStudio Help", value: "Command + Option + Slash")
            ForEach(StudioShortcut.editor) { shortcut in
                shortcutRow(shortcut.title, value: shortcut.spoken)
            }
            shortcutRow("Read Summary from Start", value: "Playback → Summary Reading menu; Summary section")
            shortcutRow("Read Summary from Selection", value: "Playback → Summary Reading menu, summary text right-click menu, or Play button options; needs a selection in the summary")
            shortcutRow("Read Selected Summary Text", value: "Playback → Summary Reading menu, summary text right-click menu, or Play button options; needs selected summary text")
            shortcutRow("Read Current Summary Sentence", value: "Playback → Summary Reading menu or summary text right-click menu")
            shortcutRow("Stop Summary Reading", value: "Playback → Summary Reading menu")
            shortcutRow("Save Segment (in its editor)", value: "Return")
            shortcutRow("Cancel a sheet or leave full-screen video", value: "Escape")
            Text("Segment changes save when you choose Save Segment. Standard Command + Z and Command + Shift + Z remain available for text editing; the separate segment-history commands do not replace them.")
            Text("Use Tab and Shift + Tab to move between controls, Space to activate buttons and toggles, and arrow keys inside lists and pickers. Enable Keyboard navigation in macOS System Settings → Keyboard to reach all controls with Tab. VoiceOver users can use standard Control + Option navigation and interaction commands; those combinations are not assigned by VidiStudio.")
        }
    }
}
