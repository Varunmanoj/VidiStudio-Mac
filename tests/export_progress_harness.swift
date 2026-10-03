import Foundation

@main struct ExportProgressHarness {
    @MainActor static func main() {
        let registry = ExportSessionRegistry()
        var cancelled: [String] = []
        let first = registry.begin(projectID: "1", projectName: "Video", status: "Preparing") { cancelled.append("1") }
        let second = registry.begin(projectID: "2", projectName: "Web", status: "Preparing") { cancelled.append("2") }
        precondition(first.fraction == nil && registry.sessions.count == 2)
        first.update(fraction: 0.6)
        first.update(fraction: 0.2)
        precondition(first.fraction == 0.6)
        first.update(fraction: nil)
        precondition(first.fraction == nil)
        first.update(fraction: -1)
        precondition(first.fraction == 0.6)
        first.update(fraction: .nan)
        precondition(first.fraction == nil)
        first.update(fraction: 1)
        precondition(first.fraction == 0.99)
        second.cancel(); second.cancel()
        precondition(cancelled == ["2"] && second.cancelling && !first.cancelling)
        first.canCancel = false
        first.cancel()
        precondition(cancelled == ["2"] && !first.cancelling)
        registry.end(first)
        precondition(registry.sessions.count == 1 && registry.sessions[0].id == second.id)
        registry.end(second)
        precondition(registry.sessions.isEmpty)
        print("Export progress session checks passed")
    }
}
