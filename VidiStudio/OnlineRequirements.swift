import Foundation

/// Pure requirements shared by controls and the final command guard. Do not
/// classify commands by an “AI” name: local speech and media preparation work offline.
enum OnlineRequirements {
    static func acceptsHost(_ host: String, service: OnlineService) -> Bool {
        let expected = service == .youtube ? "youtube.com" : service.origin.host!
        return host.lowercased() == expected || host.lowercased().hasSuffix("." + expected)
    }
    static let geminiCommands: Set<String> = ["transcribe", "generate-summary", "generate-ad-cues", "analyze", "regenerate-all", "reanalyze-segment", "reanalyze-transcript-segment", "rewrite-cue", "capture-frame", "check-api-key", "list-models", "list-voices", "validate-config", "align-imported-text", "prepare-analysis-video", "check-video-availability"]
    static func services(_ command: String, project: StudioProject?, settings: StudioSettings, extra: [String] = []) -> [OnlineService] {
        if geminiCommands.contains(command) { return [.gemini] }
        if ["synthesize-tts", "synthesize-speech", "preview-tts", "synthesize-changed"].contains(command) { return settings.ttsMode == "gemini" ? [.gemini] : [] }
        if ["import-youtube", "read-youtube-metadata", "download-youtube-audio", "youtube-playback"].contains(command) { return [.youtube] }
        if command == "download-voice" { return [.voices] }
        guard let project, project.isYouTubeURLProject else { return [] }
        if command == "prepare-video" { return [.youtube] }
        if ["export-youtube-original-audio", "export-youtube-described-audio", "combine-imported-audio"].contains(command) {
            let importedAD = extra.firstIndex(of: "--ad-source").map { i in extra.indices.contains(i + 1) && extra[i + 1] == "imported" } ?? false
            let fullMix = project.importedAudioDescription?.mode == "fullMix"
                && (command == "combine-imported-audio" || importedAD)
            let soundtrack = extra.firstIndex(of: "--soundtrack-source").flatMap { i in extra.indices.contains(i + 1) ? extra[i + 1] : nil } ?? project.audioSources?.export ?? "youtube"
            return fullMix || soundtrack == "imported" ? [] : [.youtube]
        }
        return []
    }
}

