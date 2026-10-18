import SwiftUI
import AppKit

final class VidiStudioAppDelegate: NSObject, NSApplicationDelegate {
    private var menuObservers: [NSObjectProtocol] = []
    private var menuRefreshPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                if let menu = notification.object as? NSMenu, menu !== NSApp.mainMenu {
                    NativeMenuIcons.apply(to: menu, isMenuBar: false)
                }
                self?.scheduleMenuRefresh()
            })
        }
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            NativeMenuIcons.apply(to: menu, isMenuBar: menu === NSApp.mainMenu)
            DispatchQueue.main.async {
                NativeMenuIcons.apply(to: menu, isMenuBar: menu === NSApp.mainMenu)
            }
        })
        scheduleMenuRefresh()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleMenuRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
    }

    private func scheduleMenuRefresh() {
        guard !menuRefreshPending else { return }
        menuRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.removeEmptyFormatMenu()
            if let menu = NSApp.mainMenu {
                NativeMenuIcons.apply(to: menu, isMenuBar: true)
            }
            self.menuRefreshPending = false
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
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…", systemImage: "plus") { studio.isCreatingProject = true }.keyboardShortcut("n").disabled(studio.busy)
                Button("Open Project Folder…", systemImage: "folder") { studio.openProject() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(studio.busy)
            }
        }
        .commands { StudioCommands() }
        WindowGroup("Project Editor", id: "project-editor", for: String.self) { $projectID in
            if let projectID {
                ProjectEditorWindow(projectID: projectID, openProjects: openProjects)
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("Return to All Projects and open the project again."))
            }
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.automatic)
        Settings { SettingsView(studio: studio, openProjects: openProjects) }.windowToolbarStyle(.automatic)
    }
}
