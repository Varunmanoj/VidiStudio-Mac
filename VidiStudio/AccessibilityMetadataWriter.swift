import AVFoundation
import Foundation

protocol AccessibilityMetadataWriting {
    func finalizeClosedDescriptionTrack(at url: URL) async throws
}

enum AccessibilityMetadataWriterError: LocalizedError {
    case exportNotFound
    case wrongAudioTrackCount(Int)
    case characteristicMissing
    case captionCharacteristicMissing
    case trackNameMissing

    var errorDescription: String? {
        switch self {
        case .exportNotFound: "The exported media could not be found."
        case .wrongAudioTrackCount(let count): "The export has an unexpected number of audio tracks (\(count))."
        case .characteristicMissing: "AVFoundation did not recognize the descriptive-audio characteristic."
        case .captionCharacteristicMissing: "AVFoundation did not recognize the transcript characteristic."
        case .trackNameMissing: "The export is missing a readable track name."
        }
    }
}

/// The portable engine writes names and accessibility metadata before committing an
/// output. Verify it here without remuxing, truncating names or changing languages.
struct AppleAccessibilityMetadataWriter: AccessibilityMetadataWriting {
    func finalizeClosedDescriptionTrack(at url: URL) async throws {
        try await verifyVideoTracks(at: url, requiresDescription: true)
    }

    // Retained for the native inspection harness and older callers.
    func finalizeVideoTracks(at url: URL, described: Bool, languageCode: String? = nil, languageName: String? = nil) async throws {
        try await verifyVideoTracks(at: url, requiresDescription: described)
    }

    func verifyVideoTracks(at url: URL, requiresDescription: Bool) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AccessibilityMetadataWriterError.exportNotFound
        }
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        if requiresDescription && audio.isEmpty {
            throw AccessibilityMetadataWriterError.wrongAudioTrackCount(audio.count)
        }
        var hasDescription = false
        for track in audio {
            let title = try await fullName(track)
            guard !title.isEmpty else { throw AccessibilityMetadataWriterError.trackNameMissing }
            let characteristics = try await track.load(.mediaCharacteristics)
            let described = characteristics.contains(.describesVideoForAccessibility)
            if title.contains("Audio Description") && !described {
                throw AccessibilityMetadataWriterError.characteristicMissing
            }
            hasDescription = hasDescription || described
        }
        if requiresDescription && !hasDescription {
            throw AccessibilityMetadataWriterError.characteristicMissing
        }
        let subtitles = try await asset.loadTracks(withMediaType: .subtitle)
        let text = try await asset.loadTracks(withMediaType: .text)
        for track in subtitles + text {
            let title = try await fullName(track)
            guard !title.isEmpty else { throw AccessibilityMetadataWriterError.trackNameMissing }
            let characteristics = try await track.load(.mediaCharacteristics)
            guard characteristics.contains(.transcribesSpokenDialogForAccessibility),
                  !(title.contains("AD Transcript") || title.contains("Descriptive Transcript"))
                    || characteristics.contains(.describesVideoForAccessibility) else {
                throw AccessibilityMetadataWriterError.captionCharacteristicMissing
            }
        }
    }

    private func fullName(_ track: AVAssetTrack) async throws -> String {
        let metadata = try await track.load(.metadata)
        for item in metadata where item.identifier == .quickTimeUserDataFullName {
            if let value = try await item.load(.stringValue), !value.isEmpty { return value }
        }
        return ""
    }
}
