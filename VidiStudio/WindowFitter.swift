import SwiftUI
import AppKit

struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> FittingView { FittingView() }
    func updateNSView(_ view: FittingView, context: Context) { view.fitWindow() }
    final class FittingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.tabbingMode = .disallowed
            fitWindow()
        }
        func fitWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, let screen = window.screen ?? NSScreen.main else { return }
                if window.styleMask.contains(.fullScreen) { return }
                let available = screen.visibleFrame
                if !available.contains(window.frame) {
                    var frame = window.frame
                    frame.size.width = min(frame.width, available.width)
                    frame.size.height = min(frame.height, available.height)
                    frame.origin.x = max(available.minX, min(frame.minX, available.maxX - frame.width))
                    frame.origin.y = max(available.minY, min(frame.minY, available.maxY - frame.height))
                    window.setFrame(frame, display: true)
                }
            }
        }
    }
}
