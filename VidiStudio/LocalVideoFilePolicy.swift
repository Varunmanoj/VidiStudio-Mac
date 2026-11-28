import Foundation
import UniformTypeIdentifiers

enum LocalVideoFilePolicy {
    static let maximumSizeBytes: Int64 = 2_000_000_000
    static let maximumCloudSizeBytes: Int64 = 2 * 1_024 * 1_024 * 1_024 - 500 * 1_024

    enum ImportChoice {
        case local, cloud, reduce, smaller, cancel
    }

    static func size(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return fileSize.int64Value
    }

    static func isSupportedVideo(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return true
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    static func exceedsMaximumSize(_ url: URL) throws -> Bool {
        try size(at: url) > maximumSizeBytes
    }

    static func analysisSizeWarning(_ byteCount: Int64) -> String {
        "This video (\(displaySize(byteCount))) exceeds the analysis limit. Create a smaller AI copy and keep the original for playback."
    }

    static func displaySize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
