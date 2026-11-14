import SwiftUI
import AppKit

@MainActor
final class VidiStudioAppDelegate: NSObject, NSApplicationDelegate {
    private let menus = AppMenuController()
    private var textShortcutMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NativeMenuIcons.shortcutSymbols = Dictionary(
            (StudioShortcut.editor + StudioShortcut.youtube).map { ($0.title, $0.icon) },
            uniquingKeysWith: { first, _ in first })
        menus.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menus.refresh()
        textShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { Self.handleTextShortcut(event) }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { menus.refresh() }
    func applicationWillTerminate(_ notification: Notification) {
        menus.stop()
        if let textShortcutMonitor { NSEvent.removeMonitor(textShortcutMonitor) }
    }
    static func handleTextShortcut(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard modifiers == .command || modifiers == [.command, .shift],
              let text = NSApp.keyWindow?.firstResponder as? NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
        if key == "z" {
            guard let manager = text.undoManager else { return event }
            if modifiers.contains(.shift) {
                guard manager.canRedo else { return event }; manager.redo()
            } else {
                guard manager.canUndo else { return event }; manager.undo()
            }
            return nil
        }
        guard modifiers == .command else { return event }
        let actions = ["x": "cut:", "c": "copy:", "v": "paste:", "a": "selectAll:"]
        guard let action = actions[key], NSApp.sendAction(NSSelectorFromString(action), to: text, from: nil) else { return event }
        return nil
    }

}

@main
struct VidiStudioApp: App {
    @NSApplicationDelegateAdaptor(VidiStudioAppDelegate.self) private var appDelegate
    @State private var studio = StudioModel()
    @State private var openProjects = OpenProjectRegistry()
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    var body: some Scene {
        Window("VidiStudio", id: "studio") {
            ContentView(studio: studio)
                .background(MainWindowLifetime().frame(width: 0, height: 0))
                .writingToolsBehavior(.disabled)
                .writingToolsAffordanceVisibility(.hidden)
                .frame(minWidth: 760, minHeight: 560)
                .task { YouTubeService.expireCaches(library: studio.settings.libraryPath) }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…", systemImage: "plus") { studio.beginNewProject() }.keyboardShortcut("n").disabled(studio.busy)
                Button("Open Project Folder…", systemImage: "folder") { studio.openProject() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(studio.busy)
            }
        }
        .commands { StudioCommands(studio: studio) }
        WindowGroup("Project Editor", id: "project-editor", for: String.self) { $projectID in
            Group {
            if let value = projectID {
                ProjectEditorWindow(projectID: ProjectEditorWindowValue.projectID(from: value), windowProjectID: $projectID, openProjects: openProjects)
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("Return to All Projects and open the project again."))
            }
            }.background(MainWindowLifetime().frame(width: 0, height: 0))
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        Window("My YouTube Videos", id: "youtube-browser") {
            YouTubeBrowserView(studio: studio)
                .background(MainWindowLifetime().frame(width: 0, height: 0))
        }
        Window("YouTube Details", id: "youtube-details") {
            Group {
            if let project = studio.selected, project.isYouTubeURLProject { ScrollView { YouTubeDetailsView(studio: studio, project: project, startWithCaptions: studio.youtubeDetailAction == "youtube-captions") } }
            else { Text("Choose a YouTube project.").padding() }
            }.background(MainWindowLifetime().frame(width: 0, height: 0))
        }
        Settings { SettingsView(studio: studio, openProjects: openProjects) }
            .windowToolbarStyle(.unifiedCompact)
            .defaultSize(width: 980, height: 740)
    }
}
