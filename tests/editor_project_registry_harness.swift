import Foundation

@main
struct EditorProjectRegistryHarness {
    @MainActor static func main() {
        let extraA = ProjectEditorWindowValue.newWindow(for: "alpha")
        let extraB = ProjectEditorWindowValue.newWindow(for: "alpha")
        precondition(extraA != extraB, "Explicit new-window requests need distinct identities")
        precondition(ProjectEditorWindowValue.projectID(from: extraA) == "alpha")
        let switched = ProjectEditorWindowValue.replacingProject(in: extraA, with: "beta")
        precondition(ProjectEditorWindowValue.projectID(from: switched) == "beta")
        precondition(ProjectEditorWindowValue.replacingProject(in: switched, with: "alpha") == extraA, "Switching must keep the same window identity")
        precondition(ProjectEditorWindowValue.projectID(from: "legacy-project") == "legacy-project")
        precondition(ProjectEditorWindowValue.projectID(from: "vidistudio-editor:invalid") == "vidistudio-editor:invalid")
        let registry = OpenProjectRegistry()
        let first = UUID(), second = UUID()
        registry.open("alpha", name: "Alpha", owner: first)
        registry.open("beta", name: "Beta", owner: second)
        registry.close("alpha", owner: first)
        registry.open("beta", name: "Beta", owner: first)
        precondition(registry.projects.map(\.id) == ["beta"], "Switching must update the open-project settings")
        registry.close("beta", owner: first)
        precondition(registry.projects.map(\.id) == ["beta"], "Another window still owns Beta")
        registry.close("beta", owner: second)
        precondition(registry.projects.isEmpty, "The final window must release its project")
        print("PASS: new windows have distinct identities, switching preserves identity, legacy values decode, and shared project-window ownership stays consistent.")
    }
}
