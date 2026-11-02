import Foundation

struct StudioSettings { var ttsMode = "apple" }
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
        settings.ttsMode = "gemini"; precondition(needs("synthesize-tts") == [.gemini])
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
        connection.routeChanged(false)
        precondition(OnlineService.allCases.allSatisfy { connection.state($0) == .offline })
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
