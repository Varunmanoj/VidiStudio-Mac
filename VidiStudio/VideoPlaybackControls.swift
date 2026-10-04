import SwiftUI

/// Shared transport for local AVPlayer and embedded YouTube playback.
struct VideoPlaybackControls: View {
    let playback: PlaybackModel
    let duration: Double

    private func shortcut(_ id: String) -> String {
        StudioShortcut.editor.first(where: { $0.id == id })?.spoken ?? ""
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 28, height: 24)
            .accessibilityHidden(true)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { playback.seekRelative(-5, duration: duration) } label: {
                icon("gobackward.5")
            }
            .accessibilityLabel("Rewind 5 seconds")
            .accessibilityHint(shortcut("back"))
            .help("Rewind 5 seconds (\(shortcut("back")))")
            .disabled(playback.time <= 0)

            Button { playback.togglePlayback() } label: {
                icon(playback.playbackActive ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(playback.playbackActive ? "Pause video" : "Play video")
            .accessibilityHint(shortcut("play"))
            .help("\(playback.playbackActive ? "Pause" : "Play") video (\(shortcut("play")))")

            Button { playback.stopPlayback() } label: {
                icon("stop.fill")
            }
            .accessibilityLabel("Stop video")
            .accessibilityHint("Stops video and narration and returns to the beginning. \(shortcut("stop"))")
            .help("Stop video and return to the beginning (\(shortcut("stop")))")
            .disabled(!playback.playbackActive && playback.time <= 0)

            Button { playback.seekRelative(5, duration: duration) } label: {
                icon("goforward.5")
            }
            .accessibilityLabel("Fast forward 5 seconds")
            .accessibilityHint(shortcut("forward"))
            .help("Fast forward 5 seconds (\(shortcut("forward")))")
            .disabled(duration <= 0 || playback.time >= duration)
        }
        .font(.system(size: 16, weight: .medium))
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video playback controls")
    }
}
