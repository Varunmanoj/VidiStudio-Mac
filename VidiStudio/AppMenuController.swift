import AppKit

/// Preserve native command routing while finalizing the rows produced at opening.
@MainActor
final class AppMenuController: NSObject {
    private var root: NSMenu?
    private let iconDelegates = NSMapTable<NSMenu, IconDelegate>.weakToStrongObjects()
    private var rootObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var tracking: Set<ObjectIdentifier> = []
    private var pending = false
    private var updating = false
    private let editCommands: Set<String> = ["Search Project…", "Search Projects…", "Copy and Translate…", "Rename Project…"]
    private static let systemEditCommands: Set<String> = ["Undo", "Redo", "Cut", "Copy", "Paste", "Paste and Match Style", "Delete", "Select All", "AutoFill", "Start Dictation", "Start Dictation…", "Emoji & Symbols", "Writing Tools"]

    func start() {
        root = NSApp.mainMenu
        rootObservation = NSApp.observe(\.mainMenu, options: [.new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                guard let self, let menu = change.newValue ?? nil else { return }
                self.root = menu
                // Finish the framework setter before installing the presentation.
                self.refresh()
            }
        }
        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.menuChanged(notification) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { if let menu = notification.object as? NSMenu { self?.opened(menu) } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { if let menu = notification.object as? NSMenu { self?.closed(menu) } }
        })
        // The current launch menu is already constructed. Handle it before the
        // first window becomes active, including when restoring an editor.
        reconcile()
    }

    private func menuChanged(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        guard !updating else { return }
        if menu !== root, notification.name != NSMenu.didRemoveItemNotification,
           let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
           let item = menu.item(at: index) {
            // A validation pass may replace an item after menuNeedsUpdate.
            // Set only its image properties, guarded against change notifications
            // emitted while SwiftUI resolves its lazy symbol.
            if menu.title == "Edit", Self.systemEditCommands.contains(item.title) {
                if notification.name == NSMenu.didAddItemNotification {
                    // SwiftUI may call its own delegate directly during a focus
                    // change. Wait until AppKit has finished inserting the row.
                    RunLoop.main.perform(inModes: [.common]) { [weak self, weak menu] in
                        guard let self, let menu, menu.supermenu === self.root else { return }
                        self.removeSystemEditItems(from: menu)
                    }
                }
                return
            }
            updating = true
            NativeMenuIcons.applyIcon(to: item)
            updating = false
        }
        if menu === root || (menu.supermenu === root && menu.title == "Edit") {
            refresh()
        }
    }

    func stop() {
        for case let menu as NSMenu in iconDelegates.keyEnumerator() {
            if let bridge = iconDelegates.object(forKey: menu), menu.delegate === bridge {
                menu.delegate = bridge.original
            }
        }
        iconDelegates.removeAllObjects()
        rootObservation = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func refresh() {
        guard !pending, tracking.isEmpty else { return }
        pending = true
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                guard self.tracking.isEmpty else { return }
                self.reconcile()
            }
        }
    }

    private func reconcile() {
        guard !updating, let root else { return }
        updating = true
        defer { updating = false }
        // The scene declares Edit at the standard position. Retain its actual
        // owner so SwiftUI can route focus, validation and keyboard commands.
        let candidates = root.items.filter { $0.title == "Edit" }
        if candidates.count > 1, let custom = candidates.first(where: { item in
            item.submenu?.items.contains { editCommands.contains($0.title) } == true
        }) {
            for item in candidates where item !== custom { root.removeItem(item) }
        }
        for item in root.items where item.title == "Format" { root.removeItem(item) }
        if let edit = root.items.first(where: { $0.title == "Edit" })?.submenu {
            removeSystemEditItems(from: edit)
        }
        installIconDelegates(in: root)
        NativeMenuIcons.apply(to: root, isMenuBar: true)
    }

    // SwiftUI can replace all rows, including their image visibility, in its
    // delegate's menuNeedsUpdate. Decorate the final rows in that same update.
    private func installIconDelegates(in parent: NSMenu) {
        for item in parent.items {
            guard let menu = item.submenu else { continue }
            if !(menu.delegate is IconDelegate) {
                let bridge = IconDelegate(original: menu.delegate, controller: self)
                iconDelegates.setObject(bridge, forKey: menu)
                menu.delegate = bridge
            }
            installIconDelegates(in: menu)
        }
    }

    @MainActor private final class IconDelegate: NSObject, NSMenuDelegate {
        weak var original: NSMenuDelegate?
        weak var controller: AppMenuController?

        init(original: NSMenuDelegate?, controller: AppMenuController) {
            self.original = original
            self.controller = controller
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            original?.menuNeedsUpdate?(menu)
            if menu.supermenu === NSApp.mainMenu && menu.title == "Edit" {
                controller?.removeSystemEditItems(from: menu)
            }
            NativeMenuIcons.apply(to: menu)
            controller?.installIconDelegates(in: menu)
        }
    }

    private func removeSystemEditItems(from menu: NSMenu) {
        let existing = menu.items
        var commands: [NSMenuItem] = []
        for item in existing {
            if Self.systemEditCommands.contains(item.title) { continue }
            if item.isSeparatorItem && (commands.isEmpty || commands.last?.isSeparatorItem == true) { continue }
            commands.append(item)
        }
        if commands.last?.isSeparatorItem == true { commands.removeLast() }
        if commands.count != existing.count { menu.items = commands }
    }

    private func opened(_ menu: NSMenu) {
        tracking.insert(ObjectIdentifier(menu))
        // SwiftUI can restore its own delegate when focus changes, even when
        // it reuses the same menu object. Wrap that current delegate for opening.
        if let root { installIconDelegates(in: root) }
    }

    private func closed(_ menu: NSMenu) {
        tracking.remove(ObjectIdentifier(menu))
        refresh()
    }
}
