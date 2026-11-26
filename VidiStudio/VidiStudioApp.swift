import SwiftUI
import AppKit
import Carbon
import OSLog

@MainActor
final class VidiStudioAppDelegate: NSObject, NSApplicationDelegate {
    private let handoffLog = Logger(subsystem: "com.vidistudio.desktop", category: "project-handoff")
    static let receivedSharedURLs = Notification.Name("VidiStudioReceivedSharedURLs")
    private let menus = AppMenuController()
    private var textShortcutMonitor: Any?
    private var pendingSharedURLs: [URL] = []
    var openLibraryOnDemand: (() -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        enqueueSharedURLs(urls)
    }

    @objc private func receiveURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return }
        enqueueSharedURLs([url])
    }

    private func enqueueSharedURLs(_ urls: [URL]) {
        // Route through the app instead of asking SwiftUI to promote the library scene.
        handoffLog.info("URL handoff. Library registered: \(AppWindowLifetime.hasLibraryWindow); minimized: \(AppWindowLifetime.isLibraryMiniaturized)")
        pendingSharedURLs.append(contentsOf: urls)
        if !AppWindowLifetime.hasLibraryWindow { openLibraryOnDemand?() }
        NotificationCenter.default.post(name: Self.receivedSharedURLs, object: self)
    }

    func takeSharedURLs() -> [URL] {
        let urls = pendingSharedURLs
        pendingSharedURLs.removeAll()
        return urls
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dispatch an incoming project URL without Cocoa's default reopen behavior,
        // which can deminiaturize All Projects before forwarding to the app delegate.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receiveURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
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
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(VidiStudioAppDelegate.self) private var appDelegate
    @State private var studio = StudioModel()
    @State private var openProjects = OpenProjectRegistry()
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    var body: some Scene {
        Window("VidiStudio", id: "studio") {
            ContentView(studio: studio, openProjects: openProjects, appDelegate: appDelegate, openSharedEditor: { id in
                openWindow(id: "project-editor", value: id)
            })
                .background(MainWindowLifetime(isLibrary: true).frame(width: 0, height: 0))
                .writingToolsBehavior(.disabled)
                .writingToolsAffordanceVisibility(.hidden)
                .frame(minWidth: 760, minHeight: 560)
                .task { YouTubeService.expireCaches(library: studio.settings.libraryPath) }
                .onChange(of: YouTubeService.shared.googleConnectionRevision) {
                    studio.invalidateCloudPermissions()
                    studio.settings.vertexConnected = KeychainStore.hasVertexSignIn
                    NotificationCenter.default.post(name: .vidiStudioCloudAccountDidChange, object: studio)
                }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        .commands { NewProjectCommands(studio: studio) }
        .commands { StudioCommands(studio: studio) }
        WindowGroup("Project Editor", id: "project-editor", for: String.self) { $projectID in
            if let value = projectID {
                ProjectEditorWindow(projectID: ProjectEditorWindowValue.projectID(from: value), windowProjectID: $projectID, openProjects: openProjects, libraryStudio: studio)
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("Return to All Projects and open the project again."))
                    .background(MainWindowLifetime().frame(width: 0, height: 0))
            }
        }
        .defaultWindowPlacement { _, context in
            // Fill the usable display without entering a separate full-screen Space.
            let frame = context.defaultDisplay.visibleRect
            return WindowPlacement(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        }
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


extension FocusedValues {
    @Entry var newProjectHost: UUID?
}

private struct NewProjectCommands: Commands {
    let studio: StudioModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.newProjectHost) private var host

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…", systemImage: "plus") {
                beginNewProject()
            }
            .keyboardShortcut("n")
            .disabled(!studio.canBeginNewProject)
            Button("New YouTube Project…", systemImage: "play.rectangle") {
                beginNewProject(source: .youtube)
            }
            .disabled(!studio.canBeginNewProject)
            Button("New Cloud Project…", systemImage: "cloud") {
                beginNewProject(source: .cloud)
            }
            .disabled(!studio.canBeginNewProject || !studio.settings.vertexConnected)
            Divider()
            Button("Open Cloud Videos…", systemImage: "icloud.and.arrow.down") {
                openWindow(id: "studio")
                studio.openCloudVideos()
            }
            .keyboardShortcut(StudioShortcut.cloudBrowser.key, modifiers: StudioShortcut.cloudBrowser.modifiers)
            .disabled(!studio.canOpenCloudVideos)
        }
    }

    private func beginNewProject(source: NewProjectSource = .videoFile) {
        if host == nil { openWindow(id: "studio") }
        studio.beginNewProject(source: source, host: host)
    }
}
