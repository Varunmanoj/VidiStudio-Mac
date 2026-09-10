import Foundation

enum LocalVideoFilePolicy {
    static let maximumSizeBytes: Int64 = 2_000_000_000

    static func size(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return fileSize.int64Value
    }

    static func exceedsMaximumSize(_ url: URL) throws -> Bool {
        try size(at: url) > maximumSizeBytes
    }

    static func displaySize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
