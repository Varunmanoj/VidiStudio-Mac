import AVFoundation
import Foundation

protocol AccessibilityMetadataWriting {
    func finalizeSelectableDescriptionTrack(at url: URL) async throws
}

enum AccessibilityMetadataWriterError: LocalizedError {
    case exportNotFound
    case wrongAudioTrackCount(Int)
    case characteristicMissing

    var errorDescription: String? {
        switch self {
        case .exportNotFound:
            return "The new selectable export could not be found."
        case .wrongAudioTrackCount(let count):
            return "Expected two audio tracks, but found \(count)."
        case .characteristicMissing:
            return "AVFoundation did not recognize the descriptive-audio characteristic after writing it."
        }
    }
}

struct AppleAccessibilityMetadataWriter: AccessibilityMetadataWriting {
    func finalizeSelectableDescriptionTrack(at url: URL) async throws {
        let movie = AVMutableMovie(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let audioTracks = movie.tracks(withMediaType: .audio)
        guard audioTracks.count == 2 else {
            throw AccessibilityMetadataWriterError.wrongAudioTrackCount(audioTracks.count)
        }

        let originalTrack = audioTracks[0]
        let descriptionTrack = audioTracks[1]
        originalTrack.extendedLanguageTag = "en"
        descriptionTrack.extendedLanguageTag = "en"
        originalTrack.alternateGroupID = 1
        descriptionTrack.alternateGroupID = 1
        originalTrack.isEnabled = true
        descriptionTrack.isEnabled = true

        func titleMetadata(_ title: String) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem()
            item.key = AVMetadataKey.quickTimeUserDataKeyFullName as NSString
            item.keySpace = .quickTimeUserData
            item.value = title as NSString
            return item
        }

        let characteristic = AVMutableMetadataItem()
        characteristic.key = AVMetadataKey.quickTimeUserDataKeyTaggedCharacteristic as NSString
        characteristic.keySpace = .quickTimeUserData
        characteristic.value = AVMediaCharacteristic.describesVideoForAccessibility.rawValue as NSString
        originalTrack.metadata = originalTrack.metadata + [titleMetadata("Original Audio")]
        descriptionTrack.metadata = descriptionTrack.metadata + [
            titleMetadata("English - Audio Description"),
            characteristic,
        ]

        try movie.writeHeader(
            to: url,
            fileType: .mov,
            options: .addMovieHeaderToDestination
        )

        let verifiedAsset = AVURLAsset(url: url)
        let verifiedAudioTracks = try await verifiedAsset.loadTracks(withMediaType: .audio)
        guard verifiedAudioTracks.count == 2 else {
            throw AccessibilityMetadataWriterError.wrongAudioTrackCount(verifiedAudioTracks.count)
        }
        let characteristics = try await verifiedAudioTracks[1].load(.mediaCharacteristics)
        guard characteristics.contains(.describesVideoForAccessibility) else {
            throw AccessibilityMetadataWriterError.characteristicMissing
        }
    }
}
