import Foundation

/// Keep existing project-ID window values compatible while allowing explicit additional windows.
enum ProjectEditorWindowValue {
    private static let prefix = "vidistudio-editor:"
    private static let privateSession = UUID()
    private struct Reference: Codable {
        var projectID: String
        let windowID: UUID
        var privateApproval: UUID? = nil
    }
    static func projectID(from value: String) -> String { reference(value)?.projectID ?? value }
    static func newWindow(for projectID: String, privateYouTubeApproved: Bool = false) -> String {
        encode(Reference(projectID: projectID, windowID: UUID(), privateApproval: privateYouTubeApproved ? privateSession : nil))
    }
    static func preferredWindow(_ projectID: String, isPrivate: Bool) -> String {
        guard isPrivate else { return projectID }
        return encode(Reference(projectID: projectID, windowID: privateSession, privateApproval: privateSession))
    }
    static func permitsPrivateProject(_ value: String?, projectID: String) -> Bool {
        guard let value, let reference = reference(value) else { return false }
        return reference.privateApproval == privateSession && reference.projectID == projectID
    }
    static func replacingProject(in value: String, with projectID: String) -> String {
        guard var reference = reference(value), reference.privateApproval == nil else { return projectID }
        reference.projectID = projectID
        return encode(reference)
    }
    private static func reference(_ value: String) -> Reference? {
        guard value.hasPrefix(prefix), let data = Data(base64Encoded: String(value.dropFirst(prefix.count))) else { return nil }
        return try? JSONDecoder().decode(Reference.self, from: data)
    }
    private static func encode(_ reference: Reference) -> String {
        // Reference contains only a String and UUID, whose JSON encoding cannot fail.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return prefix + (try! encoder.encode(reference)).base64EncodedString()
    }
}
