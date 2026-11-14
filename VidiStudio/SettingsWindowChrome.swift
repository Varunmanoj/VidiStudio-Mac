import SwiftUI
import AppKit

@MainActor
enum AppWindowLifetime {
    private static let mainWindows = NSHashTable<NSWindow>.weakObjects()
    private static weak var settingsWindow: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func registerMainWindow(_ window: NSWindow) {
        observeClosing()
        mainWindows.add(window)
    }

    static func registerSettingsWindow(_ window: NSWindow) {
        observeClosing()
        settingsWindow = window
        closeOrphanedSettings()
    }

    private static func observeClosing() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                if window === settingsWindow { settingsWindow = nil }
                guard mainWindows.contains(window) else { return }
                mainWindows.remove(window)
                closeOrphanedSettings()
            }
        }
    }

    private static func closeOrphanedSettings() {
        // Allow an opening replacement window to register in this event cycle.
        DispatchQueue.main.async {
            guard mainWindows.allObjects.isEmpty else { return }
            settingsWindow?.close()
        }
    }
}

struct MainWindowLifetime: NSViewRepresentable {
    func makeNSView(context: Context) -> LifetimeView { LifetimeView() }
    func updateNSView(_ view: LifetimeView, context: Context) { }
    final class LifetimeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            if let window {
                AppWindowLifetime.registerMainWindow(window)
                NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            }
        }
        @objc private func windowBecameKey(_ notification: Notification) {
            if let window { AppWindowLifetime.registerMainWindow(window) }
        }
    }
}

/// Settings scenes retain a preferences-window toolbar style unless configured on their NSWindow.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.configure() }
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            if let window {
                AppWindowLifetime.registerSettingsWindow(window)
                NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            }
            configure(fitToScreen: true)
        }
        @objc private func windowBecameKey(_ notification: Notification) {
            if let window { AppWindowLifetime.registerSettingsWindow(window) }
            configure(fitToScreen: true)
        }
        func configure(fitToScreen: Bool = false) {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.toolbarStyle = .unifiedCompact
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                guard fitToScreen, let screen = window.screen ?? NSScreen.main else { return }
                let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                if frame != window.frame { window.setFrame(frame, display: true) }
            }
        }
    }
}

private struct SmoothPresentationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.985)
            .offset(y: reduceMotion || isVisible ? 0 : 6)
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(.smooth(duration: 0.22)) {
                    isVisible = true
                }
            }
            .onDisappear {
                isVisible = false
            }
    }
}

extension View {
    func smoothPresentation() -> some View {
        modifier(SmoothPresentationModifier())
    }
}
