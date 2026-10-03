import Foundation
import AVFoundation

@main struct ExportTrackInspector {
    static func main() async throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1])
        if args.contains("--finalize") {
            try await AppleAccessibilityMetadataWriter().finalizeVideoTracks(at: url, described: args.contains("--described"))
        }
        let asset = AVURLAsset(url: url)
        var result: [String: Any] = ["path": url.path, "playable": try await asset.load(.isPlayable)]
        var tracks: [String: Any] = [:]
        for (key, type) in [("audio", AVMediaType.audio), ("subtitles", AVMediaType.subtitle)] {
            var rows: [[String: Any]] = []
            for track in try await asset.loadTracks(withMediaType: type) {
                let characteristics = try await track.load(.mediaCharacteristics)
                rows.append(["language": try await track.load(.extendedLanguageTag) ?? "",
                             "describesVideo": characteristics.contains(.describesVideoForAccessibility),
                             "spokenDialog": characteristics.contains(.transcribesSpokenDialogForAccessibility),
                             "musicAndSound": characteristics.contains(.describesMusicAndSoundForAccessibility)])
            }
            tracks[key] = rows
        }
        result["tracks"] = tracks
        var groups: [String: Any] = [:]
        for (key, characteristic) in [("audio", AVMediaCharacteristic.audible), ("subtitles", AVMediaCharacteristic.legible)] {
            guard let group = try await asset.loadMediaSelectionGroup(for: characteristic) else { groups[key] = []; continue }
            var options: [[String: Any]] = []
            let item = AVPlayerItem(asset: asset)
            for option in group.options {
                var metadata: [String] = []
                for value in option.commonMetadata {
                    if let text = try await value.load(.stringValue) { metadata.append(text) }
                }
                item.select(option, in: group)
                let selected = item.currentMediaSelection.selectedMediaOption(in: group) == option
                options.append(["displayName": option.displayName, "language": option.extendedLanguageTag ?? "",
                                "metadata": metadata, "selected": selected,
                                "describesVideo": option.hasMediaCharacteristic(.describesVideoForAccessibility),
                                "spokenDialog": option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility),
                                "musicAndSound": option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility),
                                "forced": option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)])
            }
            groups[key] = options
        }
        result["groups"] = groups
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
