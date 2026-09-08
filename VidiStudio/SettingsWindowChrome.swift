import SwiftUI
import AppKit

/// Settings scenes retain a preferences-window toolbar style unless configured on their NSWindow.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.configure() }
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.toolbarStyle = .unifiedCompact
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}
