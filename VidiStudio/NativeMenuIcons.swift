import AppKit

/// Keep native command routing and validation while making SF Symbols visible.
/// AppKit 27 hides menu images unless their visibility is explicitly requested.
@MainActor
enum NativeMenuIcons {
    static func apply(to menu: NSMenu, isMenuBar: Bool = false) {
        for item in menu.items where !item.isSeparatorItem {
            if !isMenuBar {
                if item.image == nil, let symbol = symbol(for: item) {
                    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                if item.image != nil {
                    if #available(macOS 27.0, *) {
                        if item.preferredImageVisibility != .visible {
                            item.preferredImageVisibility = .visible
                        }
                    }
                }
            }
            if let submenu = item.submenu { apply(to: submenu) }
        }
    }

    private static func symbol(for item: NSMenuItem) -> String? {
        // Responder selectors cover system-owned commands without depending on
        // their localized titles or replacing their targets and enabled states.
        if let action = item.action {
            switch NSStringFromSelector(action) {
            case "undo:": return "arrow.uturn.backward"
            case "redo:": return "arrow.uturn.forward"
            case "cut:": return "scissors"
            case "copy:": return "document.on.document"
            case "paste:", "pasteAsPlainText:", "pasteAsRichText:": return "document.on.clipboard"
            case "delete:": return "delete.left"
            case "selectAll:": return "checkmark.square"
            case "performClose:": return "xmark"
            case "performMiniaturize:": return "minus"
            case "performZoom:", "zoom:": return "arrow.up.left.and.arrow.down.right"
            case "toggleFullScreen:": return "arrow.up.left.and.arrow.down.right"
            case "arrangeInFront:": return "macwindow.on.rectangle"
            case "hide:": return "eye.slash"
            case "hideOtherApplications:": return "rectangle.on.rectangle.slash"
            case "unhideAllApplications:": return "eye"
            case "terminate:": return "power"
            case "orderFrontCharacterPalette:": return "face.smiling"
            case "startDictation:": return "mic"
            case "showHelp:": return "questionmark.circle"
            default: break
            }
        }
        switch item.title {
        case "Settings…", "Settings...": return "gearshape"
        case "Services": return "gearshape.2"
        case "Summary Reading": return "speaker.wave.2"
        case "Editor Sections": return "rectangle.split.3x1"
        case "Segments": return "timeline.selection"
        case "Analysis": return "sparkles"
        case "Narration": return "speaker.wave.2"
        case "Bring All to Front": return "macwindow.on.rectangle"
        case "Move & Resize": return "arrow.up.left.and.arrow.down.right"
        case "Center": return "dot.scope"
        case "Fill": return "arrow.up.left.and.arrow.down.right"
        case "Left", "Move to Left Side of Screen": return "rectangle.lefthalf.filled"
        case "Right", "Move to Right Side of Screen": return "rectangle.righthalf.filled"
        case "Top": return "rectangle.tophalf.filled"
        case "Bottom": return "rectangle.bottomhalf.filled"
        case "Return to Previous Size": return "arrow.uturn.backward"
        default:
            // Window-list entries are created dynamically by AppKit.
            if item.menu === NSApp.windowsMenu { return "macwindow" }
            return nil
        }
    }
}
