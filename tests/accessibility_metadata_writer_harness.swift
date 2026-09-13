import Foundation

@main
struct AccessibilityMetadataWriterHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw AccessibilityMetadataWriterError.exportNotFound
        }
        try await AppleAccessibilityMetadataWriter().finalizeClosedDescriptionTrack(
            at: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        print("Apple descriptive-audio and caption characteristics verified")
    }
}
