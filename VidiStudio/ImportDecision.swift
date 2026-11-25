import AppKit

struct ImportIssueNotice: Decodable {
    let title: String
    let message: String
    let token: String?
}

@MainActor
private final class ImportDecisionMenuTarget: NSView {
    let buttons: [NSButton]

    init(buttons: [NSButton]) {
        self.buttons = buttons
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    @objc func select(_ sender: NSMenuItem) {
        guard buttons.indices.contains(sender.tag) else { return }
        buttons[sender.tag].performClick(nil)
    }
}

@MainActor
enum ImportDecision {
    case cancel
    case proceed
    case alternative

    static func show(title: String, message: String, canContinue: Bool = true, alternative: String? = nil) -> Self {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let okay = alert.addButton(withTitle: "Okay")
        let proceed = canContinue ? alert.addButton(withTitle: "Import Anyway") : nil
        let other = alternative.map { alert.addButton(withTitle: $0) }
        // The same scoped actions are available by right-click or the keyboard
        // context-menu command. Invoke the real buttons to preserve modal results.
        let menu = NSMenu()
        menu.autoenablesItems = false
        let menuTarget = ImportDecisionMenuTarget(buttons: alert.buttons)
        func add(_ button: NSButton, symbol: String) {
            let item = NSMenuItem(title: button.title, action: #selector(ImportDecisionMenuTarget.select(_:)), keyEquivalent: "")
            item.target = menuTarget
            item.tag = menu.numberOfItems
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            menu.addItem(item)
        }
        add(okay, symbol: "xmark.circle")
        if let proceed { add(proceed, symbol: "square.and.arrow.down") }
        if let other { add(other, symbol: "folder") }
        alert.layout()
        let window = alert.window
        for button in alert.buttons { button.menu = menu }
        window.contentView?.menu = menu
        window.contentView?.addSubview(menuTarget)
        // Escape and Return both select the safe choice. Never bind the override
        // to a default keyboard equivalent.
        for button in alert.buttons.dropFirst() { button.keyEquivalent = "" }
        window.defaultButtonCell = okay.cell as? NSButtonCell
        okay.keyEquivalent = "\r"
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.modalWindow === window, event.window === window,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  [36, 53, 76].contains(event.keyCode) else { return event }
            okay.performClick(nil)
            return nil
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            withExtendedLifetime(menuTarget) {}
        }
        switch alert.runModal() {
        case .alertSecondButtonReturn: return canContinue ? .proceed : .alternative
        case .alertThirdButtonReturn: return .alternative
        default: return .cancel
        }
    }
}
