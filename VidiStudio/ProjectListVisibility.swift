import Foundation

/// Per-user list visibility, stored outside portable project folders.
struct ProjectListVisibility {
    static let didChange = Notification.Name("VidiStudioProjectListVisibilityDidChange")
    private static let key = "removedProjectFolders"
    private let defaults: UserDefaults
    private(set) var removedFolders: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        removedFolders = Set((defaults.stringArray(forKey: Self.key) ?? []).map {
            ProjectFolderIdentity.normalize(URL(fileURLWithPath: $0)).path
        })
    }
    func isRemoved(_ folder: URL) -> Bool {
        removedFolders.contains(ProjectFolderIdentity.normalize(folder).path)
    }
    mutating func remove(_ folder: URL) { setRemoved(folder, true) }
    mutating func restore(_ folder: URL) { setRemoved(folder, false) }
    private mutating func setRemoved(_ folder: URL, _ removed: Bool) {
        let path = ProjectFolderIdentity.normalize(folder).path
        let changed: Bool
        if removed { changed = removedFolders.insert(path).inserted }
        else { changed = removedFolders.remove(path) != nil }
        guard changed else { return }
        defaults.set(removedFolders.sorted(), forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
