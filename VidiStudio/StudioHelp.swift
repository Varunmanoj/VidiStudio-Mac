import AppKit

/// Keep native Help registration and routing shared by Settings and the Help menu.
@MainActor enum StudioHelp {
    static let bookName = "Varunmanojkumar.VidiStudio.help.v2"

    static func open(anchor: String = "index") {
        NSHelpManager.shared.registerBooks(in: Bundle.main)
        NSHelpManager.shared.openHelpAnchor(anchor, inBook: bookName)
    }
}
