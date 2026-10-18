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
        case "Edit Audio description Segment…", "Edit Audio Description Segment…", "Edit Transcript Segment…", "Edit Segment…", "Rename":
            return "pencil"
        case "Play from Audio description", "Play from Audio Description", "Play from Transcript":
            return "play.fill"
        case "Skip to Audio description", "Skip to Audio Description", "Skip to Transcript":
            return "forward.end.fill"
        case "Synthesize This Segment", "Regenerate Segment Narration", "Synthesize Changed Segments":
            return "waveform"
        case "Synthesize Narration":
            return "speaker.wave.2"
        case "Rewrite to Fit", "Re-Analyze This Segment…", "Analyze Video…", "Generate Audio Descriptions", "Regenerate Audio Descriptions…":
            return "sparkles"
        case "Delete Segment Audio…", "Delete All Narration Audio…":
            return "speaker.slash"
        case "Delete Segment…", "Delete Selected Segments…", "Delete Project…", "Delete Transcript…", "Delete Summary…", "Delete Descriptions…", "Delete Current Page…":
            return "trash"
        case "Open Project":
            return "macwindow.badge.plus"
        case "Open in Project Folder", "Show Project in Finder", "Open Project Folder…":
            return "folder"
        case "Export…", "Export":
            return "square.and.arrow.up"
        case "Choose Content to Delete…":
            return "eraser"
        case "Generate Video Details & Timeline Pictures", "Regenerate Video Details & Timeline Pictures…":
            return "photo.on.rectangle.angled"
        case "Generate Transcript", "Regenerate Transcript…":
            return "text.bubble"
        case "Generate Summary", "Regenerate Summary…":
            return "text.alignleft"
        case "Read from Start", "Read Summary from Start":
            return "forward.end"
        case "Read from Selection", "Read Summary from Selection":
            return "text.cursor"
        case "Read Selected Text Only", "Read Selected Summary Text":
            return "quote.bubble"
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
            if item.title.hasPrefix("Generating Audio") || item.title.hasPrefix("Currently Generating AD") || item.title.hasPrefix("Synthesizing") {
                return "rays"
            }
            if item.title.hasPrefix("Queued for Audio") {
                return "clock.arrow.circlepath"
            }
            // Window-list entries are created dynamically by AppKit.
            if item.menu === NSApp.windowsMenu { return "macwindow" }
            return nil
        }
    }
}
