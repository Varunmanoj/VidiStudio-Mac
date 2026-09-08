import SwiftUI
import AppKit

@main
struct VidiStudioApp: App {
    @State private var studio = StudioModel()
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    var body: some Scene {
        Window("VidiStudio", id: "studio") {
            ContentView(studio: studio)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { studio.isCreatingProject = true }.keyboardShortcut("n").disabled(studio.busy)
                Button("Open Project Folder…") { studio.openProject() }.keyboardShortcut("o").disabled(studio.busy)
            }
        }
        .commands { StudioCommands() }
        Window("VidiStudio Help", id: "help") { StudioHelpView() }.defaultSize(width: 740, height: 650)
        Settings { SettingsView(studio: studio) }.windowToolbarStyle(.unifiedCompact)
    }
}
