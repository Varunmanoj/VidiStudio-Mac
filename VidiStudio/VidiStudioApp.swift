import SwiftUI
import AppKit

final class VidiStudioAppDelegate: NSObject, NSApplicationDelegate {
    private var menuObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object as? NSMenu === NSApp.mainMenu else { return }
            DispatchQueue.main.async { self?.removeEmptyFormatMenu() }
        }
        DispatchQueue.main.async { self.removeEmptyFormatMenu() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { self.removeEmptyFormatMenu() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let menuObserver {
            NotificationCenter.default.removeObserver(menuObserver)
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
