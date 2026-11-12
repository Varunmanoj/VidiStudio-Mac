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
    private(set) var resource: String?
    private(set) var playing = false
    private var player: AVAudioPlayer?
    private var delegate: SoundPreviewDelegate?
    private var generation = UUID()

    init() {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    func isPlaying(_ sound: String) -> Bool { resource == sound && playing }
    func toggle(_ sound: String) {
        if resource == sound, let player {
            if playing { player.pause(); playing = false }
            else { playing = player.play() }
            return
        }
        stop()
        guard let url = Bundle.main.url(forResource: sound, withExtension: "wav"),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        let id = generation
        delegate = SoundPreviewDelegate { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == id else { return }
                self.stop()
            }
        }
        next.delegate = delegate
        player = next
        resource = sound
        playing = next.play()
        if !playing { stop() }
    }
    func stop() {
        generation = UUID()
        player?.stop(); player = nil; delegate = nil
        resource = nil; playing = false
    }
}

struct SettingsSoundRow: View {
    let title: String
    let resource: String
    let identifier: String
    let menuIdentifier: String
    @Binding var enabled: Bool
    @Bindable var preview: SettingsSoundPreview
    private var previewTitle: String { "\(preview.isPlaying(resource) ? "Pause" : "Play") sound: \(title)" }
    var body: some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: $enabled).accessibilityIdentifier(identifier)
            Button { preview.toggle(resource) } label: {
                Text(preview.isPlaying(resource) ? "\u{e034}" : "\u{e037}")
                    .font(.custom("MaterialSymbolsRounded-Regular", size: 20))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(previewTitle)
            .accessibilityIdentifier(identifier + "-preview")
            .help(previewTitle)
        }
        .contextMenu {
            Toggle(title, isOn: $enabled).accessibilityIdentifier(menuIdentifier)
            Button(previewTitle) { preview.toggle(resource) }
                .accessibilityIdentifier(identifier + "-preview-menu")
        }
    }
}
