import Foundation
import Observation

/// Shared across windows, with cancellation routed to the model running the export.
@MainActor @Observable final class ExportSession: Identifiable {
    let id = UUID()
    let projectID: String
    let projectName: String
    var status: String
    private(set) var fraction: Double?
    var cancelling = false
    var canCancel = true
    @ObservationIgnored private let cancelAction: () -> Void
    @ObservationIgnored private var highestFraction = 0.0

    init(projectID: String, projectName: String, status: String, cancel: @escaping () -> Void) {
        self.projectID = projectID
        self.projectName = projectName
        self.status = status
        cancelAction = cancel
    }

    func update(fraction value: Double?) {
        guard let value, value.isFinite else { fraction = nil; return }
        // Completion includes native metadata finalization after the engine exits.
        highestFraction = max(highestFraction, min(0.99, max(0, value)))
        fraction = highestFraction
    }

    func cancel() {
        guard canCancel, !cancelling else { return }
        cancelling = true
        status = "Stopping the export…"
        cancelAction()
    }
}

@MainActor @Observable final class ExportSessionRegistry {
    static let shared = ExportSessionRegistry()
    private(set) var sessions: [ExportSession] = []

    func begin(projectID: String, projectName: String, status: String, cancel: @escaping () -> Void) -> ExportSession {
        let session = ExportSession(projectID: projectID, projectName: projectName, status: status, cancel: cancel)
        sessions.append(session)
        return session
    }

    func end(_ session: ExportSession) {
        sessions.removeAll { $0.id == session.id }
    }
}
