import SwiftUI

@main
struct VidiStudioApp: App {
    @State private var studio = StudioModel()
    var body: some Scene {
        WindowGroup {
            ContentView(studio: studio)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Video…") { studio.importVideo() }.keyboardShortcut("n").disabled(studio.busy)
                Button("Open Project Folder…") { studio.openProject() }.keyboardShortcut("o").disabled(studio.busy)
            }
        }
        .commands { StudioCommands() }
        Window("VidiStudio Help", id: "help") { StudioHelpView() }.defaultSize(width: 740, height: 650)
        Settings { SettingsView(studio: studio) }.windowToolbarStyle(.unifiedCompact)
    }
}
