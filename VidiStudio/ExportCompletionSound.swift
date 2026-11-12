import AVFoundation

/// Called once at the end of an operation, after native export finalization.
@MainActor
final class ExportCompletionSound {
    static let shared = ExportCompletionSound()
    private var player: AVAudioPlayer?

    static func shouldPlay(command: String, enabled: Bool, succeeded: Bool, cancelled: Bool, hasOutput: Bool) -> Bool {
        enabled && succeeded && !cancelled && hasOutput &&
            (command.hasPrefix("export-") || command == "combine-imported-audio")
    }

    func complete(command: String, enabled: Bool, succeeded: Bool, cancelled: Bool, hasOutput: Bool) {
        guard Self.shouldPlay(command: command, enabled: enabled, succeeded: succeeded,
                              cancelled: cancelled, hasOutput: hasOutput),
              let url = Bundle.main.url(forResource: "descend", withExtension: "wav") else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
