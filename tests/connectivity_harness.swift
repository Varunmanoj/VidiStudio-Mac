import Foundation
import AppKit

struct StudioSettings { var ttsMode = "apple"; var narrationService: OnlineService? { ttsMode == "elevenlabs" ? .elevenlabs : ttsMode == "sarvam" ? .sarvam : ttsMode == "gemini" ? .gemini : nil } }
struct AudioSourceSettings { var export = "youtube" }
struct ImportedAudioDescription { var mode = "narration" }
struct StudioProject {
    var isYouTubeURLProject = false
    var duration = 10.0
    var audioSources: AudioSourceSettings?
    var importedAudioDescription: ImportedAudioDescription?
}
@main struct ConnectivityHarness {
    @MainActor static func main() async {
        _ = NSApplication.shared
        precondition(OnlineRequirements.acceptsHost("m.youtube.com", service: .youtube))
        precondition(OnlineRequirements.acceptsHost("www.youtube.com", service: .youtube))
        precondition(!OnlineRequirements.acceptsHost("youtube.com.portal.example", service: .youtube))
        precondition(!OnlineRequirements.acceptsHost("login.example", service: .youtube))
        var settings = StudioSettings()
        var project = StudioProject()
        func needs(_ command: String, _ extra: [String] = []) -> [OnlineService] {
            OnlineRequirements.services(command, project: project, settings: settings, extra: extra)
        }
        for command in ["import-video", "prepare-video", "save-summary", "export-audio", "export-subtitles", "doctor", "synthesize-tts"] { precondition(needs(command).isEmpty, command) }
        for command in OnlineRequirements.geminiCommands { precondition(needs(command) == [.gemini], command) }
        for command in ["analyze", "regenerate-all", "transcribe", "generate-summary", "generate-ad-cues",
                        "reanalyze-segment", "rewrite-cue", "capture-frame", "translate-results"] {
            precondition(OnlineRequirements.requiresAIConnection(command, usesGeminiNarration: false), command)
        }
        for command in ["import-video", "save-summary", "check-api-key", "synthesize-tts"] {
            precondition(!OnlineRequirements.requiresAIConnection(command, usesGeminiNarration: false), command)
        }
        precondition(OnlineRequirements.requiresAIConnection("synthesize-tts", usesGeminiNarration: true))
        precondition(AIConnection.allCases.filter { $0.supports(existingBucketVideo: true, narration: false) } == [.googleSignIn])
        precondition(AIConnection.allCases.filter { $0.supports(existingBucketVideo: false, narration: true) } == [.developer, .googleSignIn])
        precondition(needs("translate-results") == [.gemini])
        precondition(needs("copy-results").isEmpty)
        settings.ttsMode = "gemini"; precondition(needs("synthesize-tts") == [.gemini])
        settings.ttsMode = "sarvam"; precondition(needs("synthesize-tts") == [.sarvam])
        settings.ttsMode = "piper"; precondition(needs("synthesize-tts").isEmpty)
        project.isYouTubeURLProject = true
        precondition(needs("prepare-video") == [.youtube])
        precondition(needs("export-youtube-original-audio") == [.youtube])
        project.audioSources = AudioSourceSettings(export: "imported")
        precondition(needs("export-youtube-original-audio").isEmpty)
        precondition(needs("export-youtube-original-audio", ["--soundtrack-source", "youtube"]) == [.youtube])
        project.audioSources = nil
        project.importedAudioDescription = ImportedAudioDescription(mode: "fullMix")
        precondition(needs("combine-imported-audio").isEmpty)
        precondition(needs("export-youtube-described-audio", ["--ad-source", "imported"]).isEmpty)
        precondition(needs("export-youtube-described-audio", ["--ad-source", "generated"]) == [.youtube])
        precondition(needs("export-audio").isEmpty)
        project.duration = 0
        precondition(needs("inspect-original-audio").isEmpty)
        let connection = ConnectivityService(monitoring: false, probe: { $0 != .gemini })
        precondition(connection.state(.youtube) == .checking)
        await connection.waitForInitialCheck(.youtube)
        precondition(connection.available(.youtube))
        connection.routeChanged(false)
        await connection.waitForInitialCheck(.youtube)
        precondition(OnlineService.allCases.allSatisfy { connection.state($0) == .offline })
        for provider in [OnlineService.gemini, .sarvam, .elevenlabs] {
            let alert = connection.voiceFailureAlert(provider, fallback: "Sample failed")
            precondition(alert.messageText == "Internet Connection Required")
            precondition(alert.informativeText.contains(provider.name))
            precondition(alert.informativeText.contains("Saved audio"))
            precondition(alert.buttons.count == 1)
            for name in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
                alert.window.appearance = NSAppearance(named: name)
                alert.layout()
                let content = alert.window.contentView!
                let close = alert.buttons[0]
                precondition(close.isEnabled && close.frame.width > 0)
                precondition(content.bounds.contains(content.convert(close.bounds, from: close)))
            }
        }
        for provider in [OnlineService.gemini, .sarvam, .elevenlabs] {
            settings.ttsMode = provider.rawValue
            for command in ["synthesize-tts", "synthesize-speech", "synthesize-changed", "preview-tts"] { precondition(needs(command) == [provider]) }
            var warning = VoiceSelectionWarning()
            precondition(warning.shouldWarn(provider, state: .offline))
            precondition(!warning.shouldWarn(provider, state: .offline))
            precondition(!warning.shouldWarn(provider, state: .checking))
            precondition(!warning.shouldWarn(provider, state: .unreachable))
            precondition(!warning.shouldWarn(provider, state: .available))
            precondition(warning.shouldWarn(provider, state: .offline))
            precondition(!warning.shouldWarn(nil, state: .available))
            precondition(warning.shouldWarn(provider, state: .offline))
        }
        // Sample commands can replay cached audio offline; failures present the warning at their UI owner.
        precondition(needs("preview-sarvam-sample").isEmpty)
        connection.routeChanged(true)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(connection.state(.gemini) == .unreachable)
        precondition(connection.available(.youtube) && connection.available(.voices))
        let delayed = ConnectivityService(monitoring: false, probe: { _ in try? await Task.sleep(for: .milliseconds(100)); return true })
        delayed.routeChanged(true); delayed.routeChanged(false)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(OnlineService.allCases.allSatisfy { delayed.state($0) == .offline })
        // The shared monitor is isolated from the host network in these tests.
        ConnectivityService.shared.routeChanged(false)
        var cancelled = false
        let watch = ConnectionRecoveryWatch(gracePeriod: 0.01) { cancelled = true }
        watch.consume(["networkService":"youtube", "networkActive":true])
        try? await Task.sleep(for: .milliseconds(600))
        precondition(cancelled && watch.interrupted); watch.stop()
        cancelled = false
        let local = ConnectionRecoveryWatch(gracePeriod: 0.01) { cancelled = true }
        local.consume(["networkService":"youtube", "networkActive":true])
        local.consume(["networkService":"youtube", "networkActive":false])
        try? await Task.sleep(for: .milliseconds(600))
        precondition(!cancelled); local.stop()
        print("PASS: online requirements, source overrides, connection transitions, stale checks, recovery grace, and local-stage continuation")
    }
}
