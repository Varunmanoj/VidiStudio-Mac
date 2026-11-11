import SwiftUI
import AppKit

@MainActor
final class VidiStudioAppDelegate: NSObject, NSApplicationDelegate {
    private var menuObservers: [NSObjectProtocol] = []
    private var menuRefreshPending = false
    private var applyingMenuDecoration = false
    private var textShortcutMonitor: Any?
    private var trackingMenus: Set<ObjectIdentifier> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeMenuIcons.shortcutSymbols = Dictionary(
            (StudioShortcut.editor + StudioShortcut.youtube).map { ($0.title, $0.icon) },
            uniquingKeysWith: { first, _ in first })
        textShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { Self.handleTextShortcut(event) }
        }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, !self.applyingMenuDecoration else { return }
                    if self.trackingMenus.isEmpty { self.scheduleMenuRefresh() }
                    else if let menu = notification.object as? NSMenu, menu !== NSApp.mainMenu {
                        self.decorateApplicationItems(menu)
                    }
                }
            })
        }
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let menu = notification.object as? NSMenu else { return }
                self.trackingMenus.insert(ObjectIdentifier(menu))
                self.removeSystemEditCommands()
                // A menu-bar notification names the root, so only prepare the
                // app-owned Edit submenu. Context popups name their own menu.
                if menu === NSApp.mainMenu {
                    if let edit = menu.items.first(where: { $0.title == "Edit" })?.submenu {
                        self.decorateApplicationItems(edit)
                    }
                } else { self.decorateApplicationItems(menu) }
            }
        })
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let menu = notification.object as? NSMenu else { return }
                self.trackingMenus.remove(ObjectIdentifier(menu))
                self.scheduleMenuRefresh()
            }
        })
        scheduleMenuRefresh()
    }

    func applicationDidBecomeActive(_ notification: Notification) { scheduleMenuRefresh() }

    func applicationWillTerminate(_ notification: Notification) {
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        if let textShortcutMonitor { NSEvent.removeMonitor(textShortcutMonitor) }
        textShortcutMonitor = nil
    }

    private func removeSystemEditCommands() {
        guard let root = NSApp.mainMenu, let edit = root.items.first(where: { $0.title == "Edit" }), let menu = edit.submenu else { return }
        if trackingMenus.isEmpty,
           let editIndex = root.items.firstIndex(where: { $0 === edit }),
           let viewIndex = root.items.firstIndex(where: { $0.title == "View" }), editIndex > viewIndex {
            root.removeItem(edit)
            root.insertItem(edit, at: viewIndex)
        }
        let systemTitles: Set<String> = [
            "Undo", "Redo", "Cut", "Copy", "Paste", "Paste and Match Style", "Delete", "Select All",
            "AutoFill", "Start Dictation", "Start Dictation…", "Emoji & Symbols", "Writing Tools"
        ]
        let systemActions: Set<String> = [
            "undo:", "redo:", "cut:", "copy:", "paste:", "pasteAsPlainText:", "pasteAsRichText:",
            "delete:", "selectAll:", "startDictation:", "orderFrontCharacterPalette:"
        ]
        for item in menu.items where !item.isSeparatorItem {
            if systemTitles.contains(item.title) || item.action.map({ systemActions.contains(NSStringFromSelector($0)) }) == true {
                menu.removeItem(item)
            }
        }
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) }
            else { previousWasSeparator = item.isSeparatorItem }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.numberOfItems - 1) }
        if edit.isHidden { edit.isHidden = false }
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

    private func decorateApplicationItems(_ menu: NSMenu) {
        guard !applyingMenuDecoration else { return }
        applyingMenuDecoration = true
        defer { applyingMenuDecoration = false }
        NativeMenuIcons.applyApplicationItems(to: menu)
    }

    private func decorate(_ menu: NSMenu) {
        guard !applyingMenuDecoration else { return }
        applyingMenuDecoration = true
        defer { applyingMenuDecoration = false }
        NativeMenuIcons.apply(to: menu, isMenuBar: menu === NSApp.mainMenu)
    }

    private func scheduleMenuRefresh() {
        guard !menuRefreshPending, trackingMenus.isEmpty, !applyingMenuDecoration else { return }
        menuRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.menuRefreshPending = false }
            guard self.trackingMenus.isEmpty else { return }
            self.removeEmptyFormatMenu()
            self.removeSystemEditCommands()
            if let menu = NSApp.mainMenu { self.decorate(menu) }
        }
    }

    private func removeEmptyFormatMenu() {
        guard let menu = NSApp.mainMenu,
              let formatItem = menu.items.first(where: { $0.title == "Format" }) else { return }
        menu.removeItem(formatItem)
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
            if let value = projectID {
                ProjectEditorWindow(projectID: ProjectEditorWindowValue.projectID(from: value), windowProjectID: $projectID, openProjects: openProjects)
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("Return to All Projects and open the project again."))
            }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        Window("My YouTube Videos", id: "youtube-browser") {
            YouTubeBrowserView(studio: studio)
        }
        Window("YouTube Details", id: "youtube-details") {
            if let project = studio.selected, project.isYouTubeURLProject { ScrollView { YouTubeDetailsView(studio: studio, project: project, startWithCaptions: studio.youtubeDetailAction == "youtube-captions") } }
            else { Text("Choose a YouTube project.").padding() }
        }
        Settings { SettingsView(studio: studio, openProjects: openProjects) }
            .windowToolbarStyle(.unifiedCompact)
            .defaultSize(width: 980, height: 740)
    }
}
