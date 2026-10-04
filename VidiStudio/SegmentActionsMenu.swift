import AppKit
import SwiftUI

/// Native menu-item images keep the symbols visible in the macOS popup menu.
struct SegmentActionsMenu: NSViewRepresentable {
    struct Action {
        let title: String
        let systemImage: String
        var enabled = true
        let perform: () -> Void
    }

    let actions: [Action]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.setAccessibilityLabel("Segment actions")
        button.toolTip = "More options for this description"
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let enabled = context.environment.isEnabled
        context.coordinator.actions = actions
        context.coordinator.enabled = enabled
        let menu = NSMenu()
        menu.autoenablesItems = false
        let trigger = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        trigger.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        if #available(macOS 27.0, *) { trigger.preferredImageVisibility = .visible }
        menu.addItem(trigger)
        for (index, action) in actions.enumerated() {
            let item = NSMenuItem(title: action.title, action: #selector(Coordinator.performAction(_:)), keyEquivalent: "")
            item.target = context.coordinator
            item.tag = index
            item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
            // macOS 27 normally hides images when their visibility is automatic.
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            item.isEnabled = enabled && action.enabled
            menu.addItem(item)
        }
        button.menu = menu
        button.isEnabled = enabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 24)
    }

    final class Coordinator: NSObject {
        var actions: [Action] = []
        var enabled = true

        @objc func performAction(_ sender: NSMenuItem) {
            guard enabled, actions.indices.contains(sender.tag), actions[sender.tag].enabled else { return }
            actions[sender.tag].perform()
        }
    }
}
