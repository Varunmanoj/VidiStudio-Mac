import SwiftUI
import AVKit

/// Direct AVKit integration avoids the Release overlay's superclass metadata failure
/// and lets the video resize without imposing its pixel dimensions on the window.
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var playback: PlaybackModel? = nil
    var analysisCopyActions: EditorShortcutActions? = nil
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
        view.analysisCopyActions = analysisCopyActions?.isCommandVisible("play-original-video") == true ? analysisCopyActions : nil
    }
    static func dismantleNSView(_ view: PlayerSurface, coordinator: ()) {
        view.analysisCopyActions = nil
        view.player = nil
    }
}
final class PlayerSurface: AVPlayerView, FullScreenVideoSizing, NSMenuItemValidation {
    var fullScreenFrame: NSRect?
    var analysisCopyActions: EditorShortcutActions? {
        didSet { updateContextMenuMonitor() }
    }
    private var contextMenuMonitor: Any?
    override var frame: NSRect { get { super.frame } set { super.frame = fullScreenFrame ?? newValue } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContextMenuMonitor()
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

    private func updateContextMenuMonitor() {
        if window == nil || analysisCopyActions == nil {
            if let contextMenuMonitor { NSEvent.removeMonitor(contextMenuMonitor) }
            contextMenuMonitor = nil
        } else if contextMenuMonitor == nil {
            // AVKit child views can handle context clicks before SwiftUI sees them.
            contextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    return self.showAnalysisCopyContextMenu(for: event)
                }
            }
        }
    }

    private func showAnalysisCopyContextMenu(for event: NSEvent) -> NSEvent? {
        guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
              event.window === window, let content = window?.contentView,
              let target = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
              target === self || target.isDescendant(of: self),
              let actions = analysisCopyActions, actions.isCommandVisible("play-original-video") else { return event }

        let menu = target.menu(for: event)?.copy() as? NSMenu ?? NSMenu()
        if !menu.items.isEmpty { menu.insertItem(.separator(), at: 0) }
        if actions.isCommandVisible("regenerate-ai-copy") {
            insertAnalysisCopyAction("regenerate-ai-copy", title: actions.analysisCopyActionTitle, icon: "arrow.clockwise", into: menu)
            menu.insertItem(.separator(), at: 0)
        }
        for file in ProjectVideoFile.allCases.reversed() {
            let selected = actions.resultProject.map { file.isSelectedForPlayback(in: $0) } == true
            insertAnalysisCopyAction(file.playbackCommand, title: file.playbackTitle, icon: "film", selected: selected, into: menu)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: target)
        return nil
    }

    private func insertAnalysisCopyAction(_ command: String, title: String, icon: String, selected: Bool = false, into menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(runAnalysisCopyAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        item.state = selected ? .on : .off
        NativeMenuIcons.requestVisibility(for: item)
        item.isEnabled = validateMenuItem(item)
        menu.insertItem(item, at: 0)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.representedObject as? String else { return false }
        return analysisCopyActions?.canRun(command) == true
    }

    @objc private func runAnalysisCopyAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        analysisCopyActions?.run(command)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
