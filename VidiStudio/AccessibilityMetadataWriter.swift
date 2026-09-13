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
    case invalidMovieHeader
    case handlerNamesMissing(Int)

    var errorDescription: String? {
        switch self {
        case .exportNotFound:
            return "The new Closed Audio Description export could not be found."
        case .wrongAudioTrackCount(let count):
            return "Expected two audio tracks, but found \(count)."
        case .characteristicMissing:
            return "AVFoundation did not recognize the descriptive-audio characteristic after writing it."
        case .captionCharacteristicMissing:
            return "AVFoundation did not recognize the spoken-dialog transcript characteristic after writing it."
        case .invalidMovieHeader:
            return "The QuickTime movie header could not be read safely."
        case .handlerNamesMissing(let count):
            return "Expected two audio handler names in the QuickTime movie header, but found \(count)."
        }
    }
}

struct AppleAccessibilityMetadataWriter: AccessibilityMetadataWriting {
    func finalizeClosedDescriptionTrack(at url: URL) async throws {
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

        func characteristicMetadata(_ value: AVMediaCharacteristic) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem()
            item.key = AVMetadataKey.quickTimeUserDataKeyTaggedCharacteristic as NSString
            item.keySpace = .quickTimeUserData
            item.value = value.rawValue as NSString
            return item
        }

        originalTrack.metadata = originalTrack.metadata + [titleMetadata("Original Audio")]
        descriptionTrack.metadata = descriptionTrack.metadata + [
            titleMetadata("English - Audio Description"),
            characteristicMetadata(.describesVideoForAccessibility),
        ]

        let legibleTracks = movie.tracks(withMediaType: .subtitle) + movie.tracks(withMediaType: .text)
        for track in legibleTracks {
            track.extendedLanguageTag = "en"
            track.alternateGroupID = 2
            track.isEnabled = true
            track.metadata = track.metadata + [
                characteristicMetadata(.transcribesSpokenDialogForAccessibility)
            ]
        }

        try movie.writeHeader(
            to: url,
            fileType: .mov,
            options: .addMovieHeaderToDestination
        )
        try restorePortableHandlerNames(at: url)

        let verifiedAsset = AVURLAsset(url: url)
        let verifiedAudioTracks = try await verifiedAsset.loadTracks(withMediaType: .audio)
        guard verifiedAudioTracks.count == 2 else {
            throw AccessibilityMetadataWriterError.wrongAudioTrackCount(verifiedAudioTracks.count)
        }
        let characteristics = try await verifiedAudioTracks[1].load(.mediaCharacteristics)
        guard characteristics.contains(.describesVideoForAccessibility) else {
            throw AccessibilityMetadataWriterError.characteristicMissing
        }
        let verifiedSubtitleTracks = try await verifiedAsset.loadTracks(withMediaType: .subtitle)
        let verifiedTextTracks = try await verifiedAsset.loadTracks(withMediaType: .text)
        let verifiedLegibleTracks = verifiedSubtitleTracks + verifiedTextTracks
        for track in verifiedLegibleTracks {
            let characteristics = try await track.load(.mediaCharacteristics)
            guard characteristics.contains(.transcribesSpokenDialogForAccessibility) else {
                throw AccessibilityMetadataWriterError.captionCharacteristicMissing
            }
        }
    }

    /// AVMutableMovie writes generic Core Media handler names. Keep compact
    /// portable fallbacks for tools that expose handler names instead of the
    /// richer track-title metadata. Rewrite only the Pascal-string payloads in
    /// the final `moov` atom, preserving every atom's byte length.
    private func restorePortableHandlerNames(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileLength = try handle.seekToEnd()
        var offset: UInt64 = 0
        var movieHeader: (offset: UInt64, length: UInt64)?

        while offset + 8 <= fileLength {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 16), header.count >= 8 else {
                throw AccessibilityMetadataWriterError.invalidMovieHeader
            }
            let size32 = UInt64(header.readBigEndianUInt32(at: 0))
            let type = String(data: header[4..<8], encoding: .macOSRoman)
            let length: UInt64
            if size32 == 1 {
                guard header.count >= 16 else {
                    throw AccessibilityMetadataWriterError.invalidMovieHeader
                }
                length = header.readBigEndianUInt64(at: 8)
            } else if size32 == 0 {
                length = fileLength - offset
            } else {
                length = size32
            }
            guard length >= 8, offset + length <= fileLength else {
                throw AccessibilityMetadataWriterError.invalidMovieHeader
            }
            if type == "moov" { movieHeader = (offset, length) }
            offset += length
        }

        guard let movieHeader, movieHeader.length <= UInt64(Int.max) else {
            throw AccessibilityMetadataWriterError.invalidMovieHeader
        }
        try handle.seek(toOffset: movieHeader.offset)
        guard var data = try handle.read(upToCount: Int(movieHeader.length)),
              data.count == Int(movieHeader.length) else {
            throw AccessibilityMetadataWriterError.invalidMovieHeader
        }

        let audioCount = try data.replacePascalHandlerNames(
            named: "Core Media Audio",
            with: ["Original Audio", "English AD"]
        )
        guard audioCount == 2 else {
            throw AccessibilityMetadataWriterError.handlerNamesMissing(audioCount)
        }
        _ = try data.replacePascalHandlerNames(named: "Core Media Subtitle", with: ["AD Transcript"])
        _ = try data.replacePascalHandlerNames(named: "Core Media Text", with: ["AD Transcript"])

        try handle.seek(toOffset: movieHeader.offset)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

private extension Data {
    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func replacePascalHandlerNames(named oldName: String, with replacements: [String]) throws -> Int {
        let oldBytes = Array(oldName.utf8)
        let signature = Data([UInt8(oldBytes.count)] + oldBytes)
        var ranges: [Range<Data.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = range(of: signature, in: searchStart..<endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        guard ranges.count <= replacements.count else {
            throw AccessibilityMetadataWriterError.invalidMovieHeader
        }
        for (range, replacement) in zip(ranges, replacements) {
            let newBytes = Array(replacement.utf8)
            guard newBytes.count <= oldBytes.count else {
                throw AccessibilityMetadataWriterError.invalidMovieHeader
            }
            let padded = Data([UInt8(oldBytes.count)] + newBytes + Array(repeating: 0, count: oldBytes.count - newBytes.count))
            replaceSubrange(range, with: padded)
        }
        return ranges.count
    }
}
