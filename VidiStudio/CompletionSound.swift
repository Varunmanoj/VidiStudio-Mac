import AVFoundation

/// Called once at the end of an operation, after generation is saved or native export finalization finishes.
@MainActor
final class CompletionSound {
    static let shared = CompletionSound()
    private var player: AVAudioPlayer?

    static func shouldPlay(command: String, exportEnabled: Bool, generationEnabled: Bool, succeeded: Bool,
                           cancelled: Bool, hasExportOutput: Bool, hasGeneratedProject: Bool, copyEnabled: Bool = true) -> Bool {
        guard succeeded, !cancelled else { return false }
        if command.hasPrefix("export-") || command == "combine-imported-audio" {
            return exportEnabled && hasExportOutput
        }
        if command == "regenerate-ai-copy" { return copyEnabled && hasGeneratedProject }
        switch command {
        case "transcribe", "generate-summary", "generate-ad-cues", "analyze", "regenerate-all",
             "reanalyze-transcript-segment", "reanalyze-segment":
            return generationEnabled && hasGeneratedProject
        default:
            return false
        }
    }

    func complete(command: String, exportEnabled: Bool, generationEnabled: Bool, succeeded: Bool,
                  cancelled: Bool, hasExportOutput: Bool, hasGeneratedProject: Bool, copyEnabled: Bool = true) {
        guard Self.shouldPlay(command: command, exportEnabled: exportEnabled, generationEnabled: generationEnabled,
                              succeeded: succeeded, cancelled: cancelled, hasExportOutput: hasExportOutput,
                              hasGeneratedProject: hasGeneratedProject, copyEnabled: copyEnabled),
              let url = Bundle.main.url(forResource: "descend", withExtension: "wav") else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
