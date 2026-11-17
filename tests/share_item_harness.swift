import AppKit
import Foundation

@main
struct ShareItemHarness {
    static func main() async throws {
        let supported = "https://youtu.be/dQw4w9WgXcQ"
        for object: NSItemProviderWriting in [supported as NSString, URL(string: supported)! as NSURL] {
            let item = NSExtensionItem()
            item.attachments = [NSItemProvider(object: object)]
            let result = try await SharedItemResolver.resolve([item])
            precondition(result == .youtube(URL(string: supported)!))
        }
        for object: NSItemProviderWriting in ["https://example.org" as NSString, URL(string: "https://example.org")! as NSURL] {
            let item = NSExtensionItem()
            item.attachments = [NSItemProvider(object: object)]
            do {
                _ = try await SharedItemResolver.resolve([item])
                fatalError("Invalid item was accepted")
            } catch {
                precondition(error.localizedDescription == "This link does not point to a YouTube video.")
            }
        }
        print("Safari Share URL and plain-text item-provider cases passed")
    }
}
