import SwiftUI
import AVKit

/// Direct AVKit integration avoids the Release overlay's superclass metadata failure
/// and lets the video resize without imposing its pixel dimensions on the window.
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var playback: PlaybackModel? = nil
    func makeNSView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.player = player
        playback?.videoSurface = view
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateNSView(_ view: PlayerSurface, context: Context) {
        if view.player !== player { view.player = player }
    }
    static func dismantleNSView(_ view: PlayerSurface, coordinator: ()) { view.player = nil }
}
final class PlayerSurface: AVPlayerView, FullScreenVideoSizing {
    var fullScreenFrame: NSRect?
    override var frame: NSRect { get { super.frame } set { super.frame = fullScreenFrame ?? newValue } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard fullScreenFrame == nil else { return }
        guard let window, let screen = window.screen else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        guard frame.width > visible.width || frame.height > visible.height else { return }
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        window.setFrame(frame, display: true)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
