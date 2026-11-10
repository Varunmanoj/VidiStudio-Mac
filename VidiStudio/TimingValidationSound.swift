import AVFoundation
import SwiftUI

/// Plays a bundled cue once for newly introduced errors, never on view redraws.
@MainActor @Observable
final class TimingValidationSound {
    private var previousErrors: Set<String> = []
    private var player: AVAudioPlayer?
    private var lastPlayed = Date.distantPast

    func update(errors: [String], enabled: Bool) {
        let current = Set(errors)
        let introduced = !current.subtracting(previousErrors).isEmpty
        previousErrors = current
        guard enabled, introduced, Date().timeIntervalSince(lastPlayed) > 0.35,
              let url = Bundle.main.url(forResource: "Buzzer1", withExtension: "wav") else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        lastPlayed = Date()
    }
    func stop() { player?.stop() }
}
