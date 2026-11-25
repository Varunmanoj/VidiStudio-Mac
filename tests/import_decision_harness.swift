import AppKit

@main
@MainActor
struct ImportDecisionHarness {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        app.activate()

        func check(_ name: String, appearance: NSAppearance.Name, expected: ImportDecision,
                   canContinue: Bool = true, alternative: String? = nil,
                   action: @escaping (NSWindow, [NSButton], NSMenu) -> Void) {
            app.appearance = NSAppearance(named: appearance)
            func log(_ value: String) {
                FileHandle.standardError.write(Data((value + "\n").utf8))
            }
            log("Testing \(name)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let window = app.modalWindow, let content = window.contentView, let menu = content.menu else {
                    fatalError("No modal window with scoped context actions")
                }
                func buttons(in view: NSView) -> [NSButton] {
                    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
                }
                let buttons = buttons(in: content).filter { $0.menu === menu }
                let names = ["Okay"] + (canContinue ? ["Import Anyway"] : []) + (alternative.map { [$0] } ?? [])
                precondition(Set(buttons.map(\.title)) == Set(names))
                precondition(menu.items.map(\.title) == names && menu.items.allSatisfy { $0.image != nil })
                if #available(macOS 27.0, *) {
                    precondition(menu.items.allSatisfy { $0.preferredImageVisibility == .visible })
                }
                precondition(buttons.allSatisfy { $0.isEnabled && $0.frame.width > 0 && $0.menu === menu })
                log("Visible options: \(names.joined(separator: ", "))")
                action(window, buttons, menu)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if app.modalWindow?.contentView?.menu?.items.map(\.title) == ["Okay"] + (canContinue ? ["Import Anyway"] : []) + (alternative.map { [$0] } ?? []) {
                    fatalError("Timed out waiting for \(name)")
                }
            }
            let result = ImportDecision.show(title: "Timing Warning", message: "The imported copy keeps its own timing.",
                                             canContinue: canContinue, alternative: alternative)
            precondition(result == expected, name)
            log("PASS: \(name)")
        }

        check("Okay cancels in light appearance", appearance: .aqua, expected: .cancel) { _, buttons, _ in
            buttons.first { $0.title == "Okay" }!.performClick(nil)
        }
        check("Import Anyway continues in dark appearance", appearance: .darkAqua, expected: .proceed) { _, buttons, _ in
            buttons.first { $0.title == "Import Anyway" }!.performClick(nil)
        }
        check("context command runs the override", appearance: .aqua, expected: .proceed) { _, _, menu in
            let item = menu.items[1]
            let target = item.target as? NSView
            let sent = app.sendAction(item.action!, to: item.target, from: item)
            if !sent {
                precondition(target?.responds(to: item.action!) == true && target?.window === app.modalWindow && item.isEnabled)
                _ = target?.perform(item.action!, with: item)
            }
        }
        func sendKey(_ window: NSWindow, key: UInt16, chars: String) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: chars,
                                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: key)!
            app.postEvent(event, atStart: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if app.modalWindow === window { fatalError("The modal did not respond to keyboard input") }
            }
        }
        check("Return cancels rather than importing", appearance: .aqua, expected: .cancel) { window, _, _ in
            sendKey(window, key: 36, chars: "\r")
        }
        check("Escape cancels and hard failures omit the override", appearance: .darkAqua, expected: .cancel, canContinue: false) { window, _, _ in
            sendKey(window, key: 53, chars: "\u{1b}")
        }
        check("alternative stays a separate action", appearance: .darkAqua, expected: .alternative, alternative: "Choose Another File") { _, _, menu in
            let item = menu.items[2]
            let target = item.target as? NSView
            let sent = app.sendAction(item.action!, to: item.target, from: item)
            if !sent {
                precondition(target?.responds(to: item.action!) == true && target?.window === app.modalWindow && item.isEnabled)
                _ = target?.perform(item.action!, with: item)
            }
        }
    }
}
