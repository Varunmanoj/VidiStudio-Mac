import SwiftUI
import AppKit

/// Sheet dimensions come from the presenting window, avoiding a fixed height
/// larger than the usable area on compact displays or zoomed desktops.
enum SegmentDialogLayout {
    static func size(parent: CGSize, screen: CGSize) -> CGSize {
        CGSize(width: max(1, min(780, parent.width - 32, screen.width - 64)),
               height: max(1, min(680, parent.height - 24, screen.height - 96)))
    }
}

struct SegmentDialogViewport: NSViewRepresentable {
    @Binding var size: CGSize

    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {
        view.onSize = { value in if size != value { size = value } }
        view.measure()
    }
    static func dismantleNSView(_ view: Reader, coordinator: ()) { view.stopObserving() }

    final class Reader: NSView {
        var onSize: ((CGSize) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var measuring = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                    MainActor.assumeIsolated {
                        guard let self, let changed = event.object as? NSWindow,
                              changed === self.window || changed === self.window?.sheetParent else { return }
                        self.measure()
                    }
                })
            }
            measure()
        }
        override func layout() { super.layout(); measure() }
        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }
        func measure() {
            guard !measuring else { return }
            measuring = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.measuring = false
                guard let window = self.window, let screen = window.screen ?? window.sheetParent?.screen else { return }
                let visible = screen.visibleFrame.size
                // Never use the sheet's own size as its constraint: that would
                // repeatedly shrink it while attaching to its parent.
                let parent = window.sheetParent?.contentLayoutRect.size ?? visible
                self.onSize?(SegmentDialogLayout.size(parent: parent, screen: visible))
            }
        }
    }
}
