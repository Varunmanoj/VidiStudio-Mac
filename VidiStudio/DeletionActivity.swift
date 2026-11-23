import SwiftUI

/// Shared across gallery/editor windows; file removal has no reliable percentage.
@MainActor @Observable final class DeletionActivityRegistry {
    static let shared = DeletionActivityRegistry()
    private(set) var activities: [UUID: String] = [:]
    var messages: [String] { activities.values.sorted() }
    @discardableResult func begin(title: String, projectName: String) -> UUID {
        let id = UUID(); activities[id] = "\(title) · \(projectName)"; return id
    }
    func begin(command: String, projectName: String) -> UUID? {
        if command == "cloud-delete-project-video" { return begin(title: "Deleting cloud video…", projectName: projectName) }
        guard ["delete-results", "delete-generated", "delete-export", "delete-segment-audio"].contains(command) else { return nil }
        return begin(title: "Deleting selected content…", projectName: projectName)
    }
    func finish(_ id: UUID?) { if let id { activities[id] = nil } }
}

extension Notification.Name {
    static let vidiStudioProjectDeleted = Notification.Name("VidiStudioProjectDeleted")
}

struct DeletionProgressBanner: View {
    private var registry = DeletionActivityRegistry.shared
    var body: some View {
        ForEach(registry.activities.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
            let message = registry.activities[id] ?? ""
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(message).font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(12).background(.bar)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
        }
    }
}

@MainActor @Observable final class CloudImportActivity {
    static let shared = CloudImportActivity()
    private(set) var progress: [UUID: (message: String, fraction: Double?)] = [:]

    func begin() -> UUID {
        let id = UUID()
        update(id, message: "Checking Cloud Storage access…", fraction: nil)
        return id
    }

    func update(_ id: UUID, message: String, fraction: Double?) {
        progress[id] = (message, message.hasPrefix("Downloading video:") ? fraction : nil)
    }

    func finish(_ id: UUID?) {
        if let id { progress[id] = nil }
    }
}

struct CloudImportProgressBanner: View {
    private var activity = CloudImportActivity.shared

    var body: some View {
        ForEach(activity.progress.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
            if let status = activity.progress[id] {
                Group {
                    if let fraction = status.fraction {
                        ProgressView(status.message, value: fraction)
                    } else {
                        ProgressView(status.message)
                    }
                }
                .controlSize(.small)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
    }
}
