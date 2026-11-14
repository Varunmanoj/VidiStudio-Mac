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
            // SwiftUI's native menu bridge can discard Label accessibility text.
            // Apply the saved-result icon metadata to the actual NSMenuItem.
            let prefix = "Saved result status: "
            if let metadata = [item.image?.accessibilityDescription, item.toolTip].compactMap({ $0 }).first(where: { $0.hasPrefix(prefix) }) {
                let status = String(metadata.dropFirst(prefix.count))
                let label = item.title + (status.isEmpty ? "" : ", " + status)
                if item.accessibilityLabel() != label { item.setAccessibilityLabel(label) }
            }
            if let submenu = item.submenu { apply(to: submenu) }
        }
    }

    // SwiftUI materializes some items only while opening their menu. Decorate
    // those app-owned items once; never touch system commands during tracking.
    static func applyApplicationItems(to menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            if item.image == nil, let symbol = symbol(for: item) {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            if #available(macOS 27.0, *), item.image != nil, item.preferredImageVisibility != .visible {
                item.preferredImageVisibility = .visible
            }
            if let submenu = item.submenu { applyApplicationItems(to: submenu) }
        }
    }

    private static let menuSymbols: [String: String] = [
        "AD Segment Generation": "sparkles",
        "AD Transcript Saved Results": "doc.text",
        "About VidiStudio": "info.circle",
        "Add Description Segment": "plus",
        "Add Segment": "plus",
        "Add Transcript Segment": "plus",
        "All Projects": "square.stack",
        "Sort Projects": "arrow.up.arrow.down",
        "VidiStudio Website": "globe",
        "Analysis": "sparkles",
        "Analyze Video…": "sparkles",
        "Choose What to Delete…": "eraser",
        "Clear Filter": "xmark.circle",
        "Clear Sort": "arrow.uturn.backward",
        "Close": "xmark",
        "Close All": "xmark",
        "Copy and Translate…": "doc.on.doc",
        "Delete Descriptions…": "trash",
        "Delete Project…": "trash",
        "Delete Selected Segments…": "trash",
        "Description Saved Results": "doc.text",
        "Deselect All Segments": "square",
        "Edit Audio description Segments": "pencil",
        "Edit Selected Segments…": "square.and.pencil",
        "Editor Sections": "rectangle.split.3x1",
        "Exit Full-Screen Video": "arrow.down.right.and.arrow.up.left",
        "Export…": "square.and.arrow.up",
        "Filter AD Transcript…": "line.3.horizontal.decrease.circle",
        "Filter Descriptions…": "line.3.horizontal.decrease.circle",
        "Filter Projects by Language": "translate",
        "Filter Projects by Source": "line.3.horizontal.decrease.circle",
        "Filter Transcripts…": "line.3.horizontal.decrease.circle",
        "Full-Screen Video": "arrow.up.left.and.arrow.down.right",
        "Generate Missing or Changed AD Audio": "waveform",
        "Hide Inspector": "sidebar.right",
        "Hide Preview": "video.slash",
        "Hide Project List": "sidebar.left",
        "Hide Thumbnail Images": "photo.on.rectangle",
        "Hide Timeline": "timeline.selection",
        "Import": "square.and.arrow.down",
        "Import AD Audio…": "waveform",
        "Import Descriptions…": "text.below.photo",
        "Import Existing Assets…": "square.and.arrow.down",
        "Import Original Audio…": "waveform",
        "Import Summary…": "text.alignleft",
        "Import Transcript…": "text.bubble",
        "Import YouTube Captions…": "captions.bubble",
        "Language and Saved Results…": "translate",
        "Load More Playlists": "plus",
        "Load More Videos": "plus",
        "Local Video Projects": "film",
        "Move Project to Bin…": "trash",
        "My YouTube Videos…": "play.rectangle",
        "Narration Audio": "speaker.wave.2",
        "New Project…": "plus",
        "Open Project Configuration": "doc.text",
        "Open Project Folder…": "folder",
        "Open Project Settings…": "gearshape",
        "Open Selected Project": "macwindow",
        "Open in Editor": "pencil",
        "Open in New Window": "macwindow.badge.plus",
        "Open in YouTube": "arrow.up.right.square",
        "Pause Video": "pause.fill",
        "Play Video": "play.fill",
        "Project Grid View": "square.grid.2x2",
        "Project List View": "list.bullet",
        "Read Selected Summary Text": "quote.bubble",
        "Read Summary from Selection": "text.cursor",
        "Read Summary from Start": "forward.end",
        "Refresh Videos": "arrow.clockwise",
        "Refresh YouTube Details": "arrow.clockwise",
        "Remove from List": "minus.circle",
        "Rename Project…": "pencil",
        "Reset Project Filters": "line.3.horizontal.decrease.circle",
        "Review Narration Issues…": "list.bullet.clipboard",
        "Review Narration Voices…": "person.wave.2",
        "Saved Results": "doc.text",
        "Segment Narration": "speaker.wave.2",
        "Segments": "timeline.selection",
        "Select All Segments": "checkmark.square",
        "Settings…": "gearshape",
        "Show Inspector": "sidebar.right",
        "Show Preview": "video",
        "Show Project List": "sidebar.left",
        "Show Project in Finder": "folder",
        "Show Thumbnail Images": "photo.on.rectangle",
        "Show Timeline": "timeline.selection",
        "Sort AD Transcript…": "arrow.up.arrow.down",
        "Sort Descriptions…": "arrow.up.arrow.down",
        "Sort Options…": "arrow.up.arrow.down",
        "Sort Transcripts…": "arrow.up.arrow.down",
        "Stop Narration": "stop.fill",
        "Summary Reading": "speaker.wave.2",
        "Summary Saved Results": "doc.text",
        "Transcript Saved Results": "doc.text",
        "Video Details…": "info.circle",
        "VidiStudio Help": "questionmark.circle",
        "YouTube": "play.rectangle",
        "YouTube Accounts…": "person.crop.circle",
        "YouTube Projects": "play.rectangle",
    ]
    static var shortcutSymbols: [String: String] = [:]

    private static func applicationSymbol(for title: String) -> String? {
        if let symbol = menuSymbols[title] ?? shortcutSymbols[title] { return symbol }
        switch title {
        case "Copy and Translate…": return "doc.on.doc"
        case "Select All Segments": return "checkmark.square"
        case "Deselect All Segments": return "square"
        case "Done Editing Segments", "Done Editing Summary": return "checkmark"
        case "Edit Transcript Segments", "Edit Audio Description Segments", "Edit AD Transcript Segments", "Edit Descriptions Segments", "Edit Summary", "Edit Segments", "Rename", "Rename Project…",
             "Edit Audio description Segment…", "Edit Audio Description Segment…", "Edit Transcript Segment…", "Edit Segment…": return "pencil"
        case "Open in New Window", "Open Selected Project": return "macwindow.badge.plus"
        case "Open in YouTube": return "arrow.up.right.square"
        case "Open Project Settings…": return "gearshape"
        case "Open in Project Folder", "Show Project in Finder": return "folder"
        case "Open Project Configuration": return "doc.text"
        case "Remove from List": return "minus.circle"
        case "Analysis", "Analyze Video…", "Rewrite to Fit", "Re-Analyze This Segment…", "Generate Audio Descriptions", "Regenerate Audio Descriptions…": return "sparkles"
        case "Export…": return "square.and.arrow.up"
        case "Choose Content to Delete…", "Choose What to Delete…": return "eraser"
        case "Delete Project…", "Delete Segment…", "Delete Selected Segments…": return "trash"
        case "Generate Transcript", "Regenerate Transcript…": return "text.bubble"
        case "Generate Summary", "Regenerate Summary…": return "text.alignleft"
        case "Generate Video Details & Timeline Pictures", "Regenerate Video Details & Timeline Pictures…": return "photo.on.rectangle.angled"
        case "Segment Narration", "Play Narration", "Resume Narration": return "speaker.wave.2"
        case "Pause Narration": return "pause.fill"
        case "Stop Narration": return "stop.fill"
        case "Play from Transcript", "Play from Audio description", "Play from Audio Description": return "play.fill"
        case "Skip to Transcript", "Skip to Audio description", "Skip to Audio Description": return "forward.end.fill"
        case "Synthesize This Segment", "Regenerate Segment Narration": return "waveform"
        case "Import Narration Audio…": return "square.and.arrow.down"
        case "Delete Segment Audio…": return "speaker.slash"
        default: return nil
        }
    }

    private static func symbol(for item: NSMenuItem) -> String? {
        if let symbol = applicationSymbol(for: item.title) { return symbol }
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
        case "Search Project…", "Search Projects…": return "magnifyingglass"
        case "Clear Search": return "xmark.circle"
        case "Open Result": return "arrow.up.right.square"
        case "Review Draft…": return "doc.text.magnifyingglass"
        case "Settings…", "Settings...": return "gearshape"
        case "Services": return "gearshape.2"
        case "Summary Reading": return "speaker.wave.2"
        case "Editor Sections": return "rectangle.split.3x1"
        case "Segments": return "timeline.selection"
        case "Analysis", "AD Segment Generation": return "sparkles"
        case "Narration", "Narration Audio": return "speaker.wave.2"
        case "Edit Audio description Segment…", "Edit Audio Description Segment…", "Edit Transcript Segment…", "Edit Segment…", "Rename":
            return "pencil"
        case "Play from Audio description", "Play from Audio Description", "Play from Transcript":
            return "play.fill"
        case "Skip to Audio description", "Skip to Audio Description", "Skip to Transcript":
            return "forward.end.fill"
        case "Synthesize This Segment", "Regenerate Segment Narration", "Generate Missing or Changed AD Audio":
            return "waveform"
        case "Regenerate All AD Audio…":
            return "arrow.clockwise"
        case "Review Narration Voices…":
            return "person.wave.2"
        case "Generate All AD Audio":
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
        case "Open Project Configuration":
            return "doc.text"
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
