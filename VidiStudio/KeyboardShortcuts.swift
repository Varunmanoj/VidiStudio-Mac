import SwiftUI

struct EditorShortcutActions {
    var run: (String) -> Void
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
    static let editor: [StudioShortcut] = [
        .init(id: "preview", title: "Show or Hide Preview", key: "v", modifiers: [.command, .shift], spoken: "Command + Shift + V", group: "Playback"),
        .init(id: "fullscreen", title: "Full-Screen Video", key: "f", modifiers: [.command, .option], spoken: "Command + Option + F; Escape to return", group: "Playback"),
        .init(id: "play", title: "Play or Pause", key: .space, modifiers: [.command, .shift], spoken: "Command + Shift + Space", group: "Playback"),
        .init(id: "back", title: "Seek Back 5 Seconds", key: .leftArrow, modifiers: [.command, .option], spoken: "Command + Option + Left Arrow", group: "Playback"),
        .init(id: "forward", title: "Seek Forward 5 Seconds", key: .rightArrow, modifiers: [.command, .option], spoken: "Command + Option + Right Arrow", group: "Playback"),
        .init(id: "narration", title: "Toggle Narration", key: "d", modifiers: [.command, .shift], spoken: "Command + Shift + D", group: "Playback"),
        .init(id: "descriptions", title: "Show Descriptions", key: "1", modifiers: .command, spoken: "Command + 1", group: "Editor"),
        .init(id: "transcript", title: "Show Transcript", key: "2", modifiers: .command, spoken: "Command + 2", group: "Editor"),
        .init(id: "summary", title: "Show Summary", key: "3", modifiers: .command, spoken: "Command + 3", group: "Editor"),
        .init(id: "ad-transcript", title: "Show AD Transcript", key: "4", modifiers: .command, spoken: "Command + 4", group: "Editor"),
        .init(id: "ad-overview", title: "Show AD Overview", key: "5", modifiers: .command, spoken: "Command + 5", group: "Editor"),
        .init(id: "add", title: "Add Description Segment", key: "n", modifiers: [.command, .shift], spoken: "Command + Shift + N", group: "Editor"),
        .init(id: "follow", title: "Toggle Transcript Follow", key: "f", modifiers: [.command, .shift], spoken: "Command + Shift + F", group: "Editor"),
        .init(id: "undo", title: "Undo Segment Edit", key: "z", modifiers: [.command, .option], spoken: "Command + Option + Z", group: "Editor"),
        .init(id: "redo", title: "Redo Segment Edit", key: "z", modifiers: [.command, .option, .shift], spoken: "Command + Option + Shift + Z", group: "Editor")
    ]
}
struct StudioCommands: Commands {
    @FocusedValue(\.editorShortcuts) private var editor
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Playback") { entries("Playback") }
        CommandMenu("Project Editor") { entries("Editor") }
        CommandGroup(replacing: .help) {
            Button("VidiStudio Help") { openWindow(id: "help") }.keyboardShortcut("/", modifiers: [.command, .option])
        }
    }
    @ViewBuilder private func entries(_ group: String) -> some View {
        ForEach(StudioShortcut.editor.filter { $0.group == group }) { shortcut in
            Button(shortcut.title) { editor?.run(shortcut.id) }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .disabled(editor == nil)
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
            shortcutRow("New Project", value: "Command + N")
            shortcutRow("Open Project Folder", value: "Command + O")
            shortcutRow("Settings", value: "Command + Comma")
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
                Text("Import a local video or create a YouTube project, run analysis from the inspector, review descriptions, synthesize narration, and export. Your project files and completed results are saved locally.")
                Text("Editor sections include Transcript, Summary, AD Transcript, and AD Overview. AD Overview shows segment and narration counts and generates audio with Apple voices or Gemini TTS. Settings → Narration contains the language/voice browser, samples, and the choice between saved audio playback and speaking on device without files.")
                ShortcutReferenceView()
                Button("Close Help") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
        }.frame(minWidth: 640, minHeight: 500)
    }
}
