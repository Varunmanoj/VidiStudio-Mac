import SwiftUI
import AppKit

struct EditorShortcutActions {
    var run: (String) -> Void
    var previewHidden: Bool
    var canRun: (String) -> Bool
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
        case "undo": return "arrow.uturn.backward"
        case "redo": return "arrow.uturn.forward"
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
        CommandGroup(after: .sidebar) {
            Button(editor?.previewHidden == true ? "Show Preview" : "Hide Preview", systemImage: editor?.previewHidden == true ? "video" : "video.slash") {
                editor?.run("preview")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editor == nil)
            Divider()
            Button(browser?.showProjects.wrappedValue == true ? "Hide Project List" : "Show Project List", systemImage: "sidebar.left") { browser?.showProjects.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: .command).disabled(browser == nil)
            Button(browser?.hasProject == true && browser?.showInspector.wrappedValue == true ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") { browser?.showInspector.wrappedValue.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(browser?.hasProject != true)
            Divider()
            Button("Project List View", systemImage: "list.bullet") { browser?.grid.wrappedValue = false; browser?.showProjects.wrappedValue = true }
                .keyboardShortcut("1", modifiers: [.command, .option]).disabled(browser == nil)
            Button("Project Grid View", systemImage: "square.grid.2x2") { browser?.grid.wrappedValue = true; browser?.showProjects.wrappedValue = true }
                .keyboardShortcut("2", modifiers: [.command, .option]).disabled(browser == nil)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About VidiStudio", systemImage: "info.circle") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        CommandMenu("Project") {
            Menu("Playback") {
                shortcutEntries(StudioShortcut.editor.filter { $0.group == "Playback" && $0.id != "preview" })
            }
            Menu("Editor Sections") {
                shortcutEntries(StudioShortcut.editor.filter { ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"].contains($0.id) })
            }
            Menu("Segments") {
                shortcutEntries(StudioShortcut.editor.filter { ["add", "follow", "undo", "redo"].contains($0.id) })
            }
            Divider()
            Menu("Analysis & Regeneration") { entries("Analysis") }
        }
        CommandGroup(replacing: .help) {
            Button("VidiStudio Help", systemImage: "questionmark.circle") { openWindow(id: "help") }.keyboardShortcut("/", modifiers: [.command, .option])
        }
    }
    @ViewBuilder private func entries(_ group: String) -> some View {
        shortcutEntries(StudioShortcut.editor.filter { $0.group == group })
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
            Text("The Project menu groups Playback, Editor Sections, Segments, and Analysis & Regeneration. Generation shortcuts use Command + Option + Shift. Existing content is replaced only after confirmation; Regenerate All asks before deleting generated content.")
            shortcutRow("New Project", value: "Command + N")
            shortcutRow("Open Project Folder", value: "Command + O")
            shortcutRow("Settings", value: "Command + Comma")
            shortcutRow("Show or Hide Project List", value: "Command + B")
            shortcutRow("Show or Hide Inspector", value: "Command + Shift + B; requires a selected project")
            shortcutRow("Project List View", value: "Command + Option + 1")
            shortcutRow("Project Grid View", value: "Command + Option + 2")
            shortcutRow("VidiStudio Help", value: "Command + Option + Slash")
            ForEach(StudioShortcut.editor) { shortcut in
                shortcutRow(shortcut.title, value: shortcut.spoken)
            }
            shortcutRow("Save Settings (in Settings)", value: "Command + S")
            shortcutRow("Save Segment (in its editor)", value: "Return")
            shortcutRow("Cancel a sheet or close Help", value: "Escape")
            Text("Segment changes save when you choose Save Segment. Standard Command + Z and Command + Shift + Z remain available for text editing; the separate segment-history commands do not replace them.")
            Text("Use Tab and Shift + Tab to move between controls, Space to activate buttons and toggles, and arrow keys inside lists and pickers. Enable Keyboard navigation in macOS System Settings → Keyboard to reach all controls with Tab. VoiceOver users can use standard Control + Option navigation and interaction commands; those combinations are not assigned by VidiStudio.")
        }
    }
}
struct StudioHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("VidiStudio Help").font(.largeTitle).accessibilityAddTraits(.isHeader)
                Text(AppVersionInfo.display)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("VidiStudio \(AppVersionInfo.display)")
                Text("Import a local video or create a YouTube project, run analysis from the inspector, review descriptions, synthesize narration, and export. Your project files and completed results are saved locally.")
                Text("Editor sections are ordered Transcript, Summary, Descriptions, AD Overview, and AD Transcript. Transcript shows spoken dialogue; Descriptions contains the authored AD segments; AD Overview shows segment and narration counts and generates audio with Apple voices or Gemini TTS; AD Transcript combines dialogue and AD segments chronologically. Settings → Narration contains the language and voice browser, voice samples, offline speech rate, pitch and volume controls, Restore Defaults, and the choice between saved audio playback and speaking on device without files.")
                ShortcutReferenceView()
                Button("Close Help") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
        }.frame(minWidth: 640, minHeight: 500)
    }
}
