import Foundation

enum AIConnection: CaseIterable {
    case developer, googleSignIn, express

    init(provider: String, authentication: String) {
        self = provider != "vertex" ? .developer : authentication == "express" ? .express : .googleSignIn
    }

    var title: String {
        switch self {
        case .developer: "Gemini Developer API"
        case .googleSignIn: "Vertex AI with Google sign-in"
        case .express: "Vertex AI Express API key"
        }
    }

    func supports(existingBucketVideo: Bool, narration: Bool) -> Bool {
        if existingBucketVideo { return self == .googleSignIn }
        return !narration || self != .express
    }
}

/// Pure requirements shared by controls and the final command guard. Do not
/// classify commands by an “AI” name: local speech and media preparation work offline.
enum OnlineRequirements {
    static func acceptsHost(_ host: String, service: OnlineService) -> Bool {
        let expected = service == .youtube ? "youtube.com" : service.origin.host!
        return host.lowercased() == expected || host.lowercased().hasSuffix("." + expected)
    }
    static let geminiCommands: Set<String> = ["translate-results", "transcribe", "generate-summary", "generate-ad-cues", "analyze", "regenerate-all", "reanalyze-segment", "reanalyze-transcript-segment", "rewrite-cue", "capture-frame", "check-api-key", "list-models", "list-voices", "validate-config", "align-imported-text", "prepare-analysis-video", "check-video-availability"]
    static let videoAICommands: Set<String> = ["analyze", "regenerate-all", "analyze-video", "transcribe", "generate-summary",
        "generate-ad-cues", "reanalyze-segment", "reanalyze-transcript-segment"]
    static let narrationCommands: Set<String> = ["synthesize-tts", "synthesize-speech", "preview-tts", "synthesize-changed"]
    static func requiresAIConnection(_ command: String, usesGeminiNarration: Bool) -> Bool {
        if narrationCommands.contains(command) { return usesGeminiNarration }
        return geminiCommands.contains(command) && !["check-api-key", "list-models", "list-voices", "validate-config"].contains(command)
    }
    static func services(_ command: String, project: StudioProject?, settings: StudioSettings, extra: [String] = []) -> [OnlineService] {
        if command == "elevenlabs-settings" { return [.elevenlabs] }
        if command == "check-sarvam-key" { return [.sarvam] }
        if geminiCommands.contains(command) { return [.gemini] }
        if narrationCommands.contains(command) { return settings.narrationService.map { [$0] } ?? [] }
        if ["import-youtube", "read-youtube-metadata", "download-youtube-audio", "youtube-playback"].contains(command) { return [.youtube] }
        if command == "download-voice" { return [.voices] }
        guard let project, project.isYouTubeURLProject else { return [] }
        if command == "prepare-video" { return [.youtube] }
        if project.usesStandaloneYouTubeAudio && ["export-youtube-original-audio", "export-youtube-described-audio", "combine-imported-audio"].contains(command) {
            let importedAD = extra.firstIndex(of: "--ad-source").map { i in extra.indices.contains(i + 1) && extra[i + 1] == "imported" } ?? false
            let fullMix = project.importedAudioDescription?.mode == "fullMix"
                && (command == "combine-imported-audio" || importedAD)
            let soundtrack = extra.firstIndex(of: "--soundtrack-source").flatMap { i in extra.indices.contains(i + 1) ? extra[i + 1] : nil } ?? project.audioSources?.export ?? "youtube"
            return fullMix || soundtrack == "imported" ? [] : [.youtube]
        }
        return []
    }
}


/// Rechecks must not reopen a dismissed warning before the connection recovers.
struct VoiceSelectionWarning {
    private var warnedService: OnlineService?
    mutating func shouldWarn(_ service: OnlineService?, state: ConnectionState) -> Bool {
        guard let service else { warnedService = nil; return false }
        if state == .available { warnedService = nil; return false }
        guard state == .offline || state == .unreachable else { return false }
        guard warnedService != service else { return false }
        warnedService = service
        return true
    }
}
