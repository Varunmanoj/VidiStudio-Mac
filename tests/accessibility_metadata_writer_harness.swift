import Foundation

@main
struct AccessibilityMetadataWriterHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw AccessibilityMetadataWriterError.exportNotFound
        }
        try await AppleAccessibilityMetadataWriter().finalizeSelectableDescriptionTrack(
            at: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        print("Apple descriptive-audio characteristic verified")
    }
}
