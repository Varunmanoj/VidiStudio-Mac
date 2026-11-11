import Foundation

enum ProjectListSort: String, CaseIterable {
    case lastOpened, name, duration, type

    func sorted(_ projects: [StudioProject], lastOpened: [String: Double]) -> [StudioProject] {
        projects.sorted { lhs, rhs in
            switch self {
            case .lastOpened:
                let left = ProjectOpenHistory.date(lhs, in: lastOpened)
                let right = ProjectOpenHistory.date(rhs, in: lastOpened)
                if left != right { return left > right }
            case .duration:
                let left = lhs.duration.isFinite ? lhs.duration : 0
                let right = rhs.duration.isFinite ? rhs.duration : 0
                if left != right { return left > right }
            case .type:
                if lhs.isYouTubeURLProject != rhs.isYouTubeURLProject { return !lhs.isYouTubeURLProject }
            case .name: break
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return (lhs.folder?.path ?? lhs.id) < (rhs.folder?.path ?? rhs.id)
        }
    }
}

/// Device-local history; opening or sorting never rewrites portable project files.
enum ProjectOpenHistory {
    static let key = "projectLastOpened"
    static func read(_ data: Data) -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }
    static func date(_ project: StudioProject, in history: [String: Double]) -> Double {
        let key = project.folder.map { ProjectFolderIdentity.normalize($0).path } ?? project.id
        let value = history[key] ?? project.updatedAt
        return value.isFinite ? value : 0
    }
    static func record(_ project: StudioProject, defaults: UserDefaults = .standard, now: Double = Date().timeIntervalSince1970) {
        var history = read(defaults.data(forKey: key) ?? Data())
        let folder = project.folder.map { ProjectFolderIdentity.normalize($0).path } ?? project.id
        history[folder] = now
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: key) }
    }
}
