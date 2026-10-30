import Foundation

/// Keep existing project-ID window values compatible while allowing explicit additional windows.
enum ProjectEditorWindowValue {
    private static let prefix = "vidistudio-editor:"
    private struct Reference: Codable {
        var projectID: String
        let windowID: UUID
    }
    static func projectID(from value: String) -> String { reference(value)?.projectID ?? value }
    static func newWindow(for projectID: String) -> String {
        encode(Reference(projectID: projectID, windowID: UUID()))
    }
    static func replacingProject(in value: String, with projectID: String) -> String {
        guard var reference = reference(value) else { return projectID }
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
