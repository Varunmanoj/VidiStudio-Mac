import Foundation

@main
struct ProjectManagementHarness {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-management-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{}".utf8).write(to: folder.appendingPathComponent("project.json"))
        let project = StudioProject(id: "selected", name: "Selected", folder: folder)
        let model = StudioModel()
        model.selected = project
        model.listedProjects = [project]
        let browser = ProjectBrowserActions(showProjects: nil, showInspector: nil, grid: nil, hasProject: false, listModel: model)
        precondition(!browser.canRun("open-configuration"), "Configuration must be unavailable by default")
        browser.run("open-configuration")
        precondition(model.projectManagementRequest == nil)
        model.settings.developerMode = true
        let commands = ["rename-project", "trash-project", "show-in-finder", "open-configuration"]
        for command in commands {
            precondition(browser.canRun(command), "Selected projects must support offline management")
            browser.run(command)
            precondition(model.projectManagementRequest?.action == command && model.projectManagementRequest?.project.id == "selected")
            model.projectManagementRequest = nil
        }
        model.listedProjects = []
        precondition(!browser.canRun("rename-project"), "A hidden main-list entry must not become a selection")
        let editor = ProjectBrowserActions(showProjects: nil, showInspector: nil, grid: nil, hasProject: true, editorModel: model)
        precondition(editor.canRun("rename-project") && editor.canRun("trash-project"), "Open editor projects must work with the browser closed")
        precondition(editor.canRun("open-configuration"))
        model.settings.developerMode = false
        precondition(!editor.canRun("open-configuration"))
        editor.run("open-configuration")
        precondition(model.projectManagementRequest == nil, "An already-created action must recheck Developer mode")
        model.settings.developerMode = true
        model.busy = true
        for command in commands { precondition(!editor.canRun(command)) }
        model.busy = false
        model.report.manifestUnreadable = true
        precondition(!editor.canRun("rename-project") && editor.canRun("trash-project"), "Unreadable projects still support confirmed removal")
        model.report.manifestUnreadable = false
        model.selected = nil
        for command in commands { precondition(!editor.canRun(command)) }
        print("PASS: Developer mode gates configuration off, on, and off again; offline list/editor management and busy, unreadable, hidden, and unselected guards pass.")
    }
}
