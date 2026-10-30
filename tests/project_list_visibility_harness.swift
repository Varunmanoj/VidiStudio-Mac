import Foundation

@main
struct ProjectListVisibilityHarness {
    static func main() throws {
        let suite = "vidistudio-list-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let folders = [root.appendingPathComponent("library/project"), root.appendingPathComponent("external/project")]
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["project.json", "source.mp4", "narration.wav", "export.srt"] {
                try Data("fixture \(name)".utf8).write(to: folder.appendingPathComponent(name))
            }
        }
        let files = try folders.flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
        let snapshot = try Dictionary(uniqueKeysWithValues: files.map { ($0, try Data(contentsOf: $0)) })
        let modified = try Dictionary(uniqueKeysWithValues: files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) })
        var visibility = ProjectListVisibility(defaults: defaults)
        precondition(!visibility.isRemoved(folders[0]))
        visibility.remove(folders[0])
        visibility.remove(folders[1])
        visibility.remove(folders[0].appendingPathComponent("."))
        precondition(visibility.removedFolders.count == 2, "Path aliases must not duplicate preferences")
        visibility = ProjectListVisibility(defaults: UserDefaults(suiteName: suite)!)
        precondition(folders.allSatisfy { visibility.isRemoved($0) }, "Removal must survive model restart")
        precondition(!visibility.isRemoved(root.appendingPathComponent("other/project")), "Same-name projects must remain independent")
        visibility.restore(folders[0])
        visibility = ProjectListVisibility(defaults: defaults)
        precondition(!visibility.isRemoved(folders[0]) && visibility.isRemoved(folders[1]), "Opening must restore only that project")
        for file in files {
            let bytes = try Data(contentsOf: file)
            let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            precondition(bytes == snapshot[file] && date == modified[file], "Remove/restore must not change project files")
        }
        print("PASS: Mac library/external removal persists, path aliases are handled, reopening restores one project, and project files/modified dates stay unchanged.")
    }
}
