import SwiftUI
import AVKit

/// Direct AVKit integration avoids the Release overlay's superclass metadata failure
/// and lets the video resize without imposing its pixel dimensions on the window.
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    var playback: PlaybackModel? = nil
    var previewMenu: PreviewContextMenu
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
        view.contextMenuMonitor.update(previewMenu, on: view)
    }
    static func dismantleNSView(_ view: PlayerSurface, coordinator: ()) {
        view.contextMenuMonitor.update(nil, on: view)
        view.player = nil
    }
}
final class PlayerSurface: AVPlayerView, FullScreenVideoSizing {
    var fullScreenFrame: NSRect?
    let contextMenuMonitor = PreviewContextMenuMonitor()
    override var frame: NSRect { get { super.frame } set { super.frame = fullScreenFrame ?? newValue } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        contextMenuMonitor.windowDidChange(on: self)
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

@MainActor
struct PreviewContextMenu {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        var selected = false
    }

    let actions: EditorShortcutActions
    let studio: StudioModel
    let project: StudioProject

    var groups: [[Item]] {
        var common = [Item(id: "project-settings", title: "Open Project Settings…", icon: "gearshape")]
        if actions.isCommandVisible("copy-to") {
            common.insert(Item(id: "copy-to", title: "Copy and Translate…", icon: "doc.on.doc"), at: 0)
        }

        var groups = [common]
        if actions.isCommandVisible("play-original-video"), let project = actions.resultProject {
            groups.append(ProjectVideoFile.allCases.map { file in
                Item(id: file.playbackCommand, title: file.playbackTitle, icon: "film", selected: file.isSelectedForPlayback(in: project))
            })
            if actions.isCommandVisible("regenerate-ai-copy") {
                groups.append([Item(id: "regenerate-ai-copy", title: actions.analysisCopyActionTitle, icon: "arrow.clockwise")])
            }
        } else if actions.canChooseYouTubePlayer {
            groups.append([
                Item(id: "use-youtube-player", title: "YouTube Player", icon: "play.rectangle", selected: actions.drivesYouTubePlayer),
                Item(id: "use-local-video-player", title: "Local Video Player", icon: "film", selected: actions.isUsingLocalVideoPlayer),
            ])
        }
        return groups
    }

    func canRun(_ command: String) -> Bool {
        if command == "project-settings" { return studio.canManageProject(command, project: project) }
        return actions.canRun(command)
    }

    func run(_ command: String) {
        guard canRun(command) else { return }
        if command == "project-settings" {
            studio.requestProjectManagement(command, project: project)
        } else {
            actions.run(command)
        }
    }

    @ViewBuilder var items: some View {
        let groups = self.groups
        ForEach(groups.indices, id: \.self) { index in
            if index > 0 { Divider() }
            ForEach(groups[index]) { item in
                Button(item.title, systemImage: item.selected ? "checkmark" : item.icon) { run(item.id) }
                    .accessibilityAddTraits(item.selected ? .isSelected : [])
                    .disabled(!canRun(item.id))
            }
        }
    }
}

/// Both video surfaces can consume context clicks before SwiftUI receives them.
@MainActor
final class PreviewContextMenuMonitor: NSObject, NSMenuItemValidation {
    private var menu: PreviewContextMenu?
    private var token: Any?

    func update(_ menu: PreviewContextMenu?, on surface: NSView) {
        self.menu = menu
        windowDidChange(on: surface)
    }

    func windowDidChange(on surface: NSView) {
        if surface.window == nil || menu == nil {
            if let token { NSEvent.removeMonitor(token) }
            token = nil
        } else if token == nil {
            token = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self, weak surface] event in
                MainActor.assumeIsolated {
                    guard let self, let surface else { return event }
                    return self.showPreviewContextMenu(for: event, on: surface)
                }
            }
        }
    }

    private func showPreviewContextMenu(for event: NSEvent, on surface: NSView) -> NSEvent? {
        guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
              event.window === surface.window, let content = surface.window?.contentView,
              let target = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
              target === surface || target.isDescendant(of: surface), let menu else { return event }

        let context = NSMenu()
        for group in menu.groups {
            if !context.items.isEmpty { context.addItem(.separator()) }
            for action in group {
                let item = NSMenuItem(title: action.title, action: #selector(runPreviewAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.id
                item.image = NSImage(systemSymbolName: action.icon, accessibilityDescription: nil)
                item.state = action.selected ? .on : .off
                NativeMenuIcons.requestVisibility(for: item)
                context.addItem(item)
            }
        }
        if let nativeMenu = target.menu(for: event), !nativeMenu.items.isEmpty {
            context.addItem(.separator())
            for item in nativeMenu.items {
                if let copy = item.copy() as? NSMenuItem { context.addItem(copy) }
            }
        }
        NSMenu.popUpContextMenu(context, with: event, for: target)
        return nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.representedObject as? String else { return false }
        return menu?.canRun(command) == true
    }

    @objc private func runPreviewAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        menu?.run(command)
    }
}
