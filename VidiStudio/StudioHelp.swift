import AppKit

/// Keep native Help registration and routing shared by Settings and the Help menu.
@MainActor enum StudioHelp {
    static let bookName = "Varunmanojkumar.VidiStudio.help"

    static func open() {
        NSHelpManager.shared.registerBooks(in: Bundle.main)
        NSHelpManager.shared.openHelpAnchor("index", inBook: bookName)
    }
}
