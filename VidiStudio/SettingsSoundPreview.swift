@preconcurrency import AVFoundation
import CoreText
import SwiftUI

private final class SoundPreviewDelegate: NSObject, AVAudioPlayerDelegate {
    let finished: @Sendable () -> Void
    init(finished: @escaping @Sendable () -> Void) { self.finished = finished }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) { finished() }
}

@MainActor @Observable
final class SettingsSoundPreview {
    private(set) var activeID: String?
    private(set) var playing = false
    private var player: AVAudioPlayer?
    private var delegate: SoundPreviewDelegate?
    private var generation = UUID()

    init() {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    func isPlaying(_ id: String) -> Bool { activeID == id && playing }
    func toggle(_ id: String, resource: String) {
        if activeID == id, let player {
            if playing { player.pause(); playing = false }
            else { playing = player.play() }
            return
        }
        stop()
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav"),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = generation
        delegate = SoundPreviewDelegate { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                self.stop()
            }
        }
        next.delegate = delegate
        player = next
        activeID = id
        playing = next.play()
        if !playing { stop() }
    }
    func stop() {
        generation = UUID()
        player?.stop(); player = nil; delegate = nil
        activeID = nil; playing = false
    }
}

struct SettingsSoundRow: View {
    let title: String
    let resource: String
    let identifier: String
    let menuIdentifier: String
    @Binding var enabled: Bool
    @Bindable var preview: SettingsSoundPreview
    private var previewTitle: String { "\(preview.isPlaying(identifier) ? "Pause" : "Play") sound: \(title)" }
    var body: some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: $enabled).accessibilityIdentifier(identifier)
            Button { preview.toggle(identifier, resource: resource) } label: {
                Text(preview.isPlaying(identifier) ? "\u{e034}" : "\u{e037}")
                    .font(.custom("MaterialSymbolsRounded-Regular", size: 20))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(previewTitle)
            .accessibilityIdentifier(identifier + "-preview")
            .help(previewTitle)
        }
        .contextMenu {
            Toggle(isOn: $enabled) { Label(title, systemImage: "speaker.wave.2") }.accessibilityIdentifier(menuIdentifier)
            Button(previewTitle, systemImage: preview.isPlaying(identifier) ? "pause.fill" : "play.fill") { preview.toggle(identifier, resource: resource) }
                .accessibilityIdentifier(identifier + "-preview-menu")
        }
    }
}
